import Foundation
import Observation
@preconcurrency import LLM

enum LLMEngineError: LocalizedError {
    case modelInitializationFailed

    var errorDescription: String? {
        switch self {
        case .modelInitializationFailed:
            return "Model initialization failed."
        }
    }
}

private final class GenerationProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTokenTime: Date
    private var didTimeout = false
    private var emittedToken = false

    init() {
        lastTokenTime = Date()
    }

    func markToken() {
        lock.lock()
        lastTokenTime = Date()
        emittedToken = true
        lock.unlock()
    }

    func secondsSinceLastToken() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastTokenTime)
    }

    func markTimedOut() {
        lock.lock()
        didTimeout = true
        lock.unlock()
    }

    func hasTimedOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeout
    }

    func hasEmittedToken() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return emittedToken
    }
}

private final class GenerationResponseTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var response: Any?

    func complete(with response: Any) {
        lock.lock()
        self.response = response
        completed = true
        lock.unlock()
    }

    func isCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func responseValue() -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return response
    }
}

private final class StreamTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ text: String) {
        lock.lock()
        value += text
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Observable
@MainActor
class LLMEngine {
    var isLoaded = false
    var isLoadingModel = false
    var isGenerating = false
    var modelPath: String?
    var loadError: String?
    var generationError: String?
    var lastGenerationWasCancelled = false
    var activeProfile: ModelProfile = .generic
    var modelWarnings: [String] = []

    private var llm: LLM?
    private var generationTask: Task<Void, Never>?

    private let maxPromptCharacters = AppConstants.LLMEngine.maxPromptCharacters
    private let maxHistoryMessages = AppConstants.LLMEngine.maxHistoryMessages
    private let responseStyleDefaultsKey = AppConfiguration.Keys.responseStyle
    private let samplingTemperatureDefaultsKey = AppConfiguration.Keys.samplingTemperature
    private let samplingTopKDefaultsKey = AppConfiguration.Keys.samplingTopK
    private let samplingRepeatPenaltyDefaultsKey = AppConfiguration.Keys.samplingRepeatPenalty

    func preflightModel(at url: URL) throws -> ModelValidationReport {
        try ModelValidator.validateModel(at: url)
    }

    func loadModel(at url: URL) async throws {
        stopGeneration()
        loadError = nil
        generationError = nil
        isLoadingModel = true

        do {
            let validation = try preflightModel(at: url)
            activeProfile = validation.profile
            modelWarnings = validation.warnings

            AppLogger.info(
                "Preflight passed for \(url.lastPathComponent) profile=\(validation.profile.displayName) size=\(validation.fileSizeBytes)",
                category: .model
            )

            let profile = validation.profile
            let modelURL = URL(fileURLWithPath: url.path)
            let loadedLLM: LLM = try await Task.detached(priority: .userInitiated) {
                let template: Template
                switch profile {
                case .qwen3, .lfm25, .generic:
                    // Empty system here — the real system prompt is built by
                    // systemPromptForCurrentStyle() and injected via formatPrompt().
                    template = .chatML("")
                }
                guard let loadedLLM = LLM(from: modelURL, template: template) else {
                    throw LLMEngineError.modelInitializationFailed
                }
                return loadedLLM
            }.value

            applySamplingPreset(validation.profile.sampling, to: loadedLLM)
            loadedLLM.preprocess = { input, _ in
                return input
            }
            loadedLLM.postprocess = { _ in }

            llm = loadedLLM
            modelPath = modelURL.path
            isLoaded = true
            isLoadingModel = false
            AppLogger.info("Model loaded successfully.", category: .model)
        } catch {
            llm = nil
            modelPath = nil
            isLoaded = false
            isLoadingModel = false
            loadError = "Failed to load model: \(error.localizedDescription)"
            AppLogger.error("Model load failed: \(error.localizedDescription)", category: .model)
            throw error
        }
    }

    func generate(messages: [ChatMessage], systemPrompt: String = "") -> AsyncStream<String> {
        generationTask?.cancel()
        isGenerating = true
        generationError = nil
        lastGenerationWasCancelled = false

        guard let llm else {
            isGenerating = false
            return AsyncStream { continuation in
                continuation.yield("Error: No model loaded.")
                continuation.finish()
            }
        }

        let profile = activeProfile
        let clippedMessages = trimmedHistory(messages)
        let prompt = profile.formatPrompt(messages: clippedMessages, systemPrompt: systemPromptForCurrentStyle(override: systemPrompt))
        applySamplingPreset(profile.sampling, to: llm)

        AppLogger.debug("Starting generation with profile \(profile.displayName).", category: .inference)

        let (stream, continuation) = AsyncStream<String>.makeStream()

        generationTask = Task(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isGenerating = false
                    self?.generationTask = nil
                }
                continuation.finish()
            }

            if Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.lastGenerationWasCancelled = true
                }
                return
            }

            let timeoutInterval = AppConstants.LLMEngine.generationTimeoutSeconds
            let heartbeatInterval = AppConstants.LLMEngine.streamHeartbeatIntervalSeconds
            let progress = GenerationProgressTracker()
            let responseTracker = GenerationResponseTracker()
            let streamedText = StreamTextBuffer()

            llm.history.removeAll(keepingCapacity: true)
            llm.update = { outputDelta in
                if Task.isCancelled {
                    return
                }

                guard let outputDelta else { return }
                let cleaned = outputDelta.replacingOccurrences(of: "<|im_end|>", with: "")
                if !cleaned.isEmpty {
                    streamedText.append(cleaned)
                    progress.markToken()
                    continuation.yield(cleaned)
                }
            }

            let responseTask = Task {
                let response = await llm.respond(to: prompt)
                responseTracker.complete(with: response)
            }

            while !Task.isCancelled {
                if responseTracker.isCompleted() {
                    break
                }

                if progress.secondsSinceLastToken() > timeoutInterval {
                    progress.markTimedOut()
                    responseTask.cancel()
                    llm.stop()
                    await MainActor.run { [weak self] in
                        self?.generationError = "Generation timeout: The model became unresponsive."
                    }
                    continuation.finish()
                    break
                }

                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
            }

            llm.update = { _ in }

            if progress.hasTimedOut() {
                return
            }

            if Task.isCancelled {
                responseTask.cancel()
                llm.stop()
                await MainActor.run { [weak self] in
                    self?.lastGenerationWasCancelled = true
                }
                return
            }

            guard responseTracker.isCompleted() else {
                responseTask.cancel()
                llm.stop()
                await MainActor.run { [weak self] in
                    self?.generationError = "Generation stopped before completion."
                }
                return
            }

            let responseAny: Any = responseTracker.responseValue() ?? ""
            if let finalResponse = extractStringResponse(from: responseAny)?
                .replacingOccurrences(of: "<|im_end|>", with: ""),
               !finalResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let streamed = streamedText.snapshot()
                if streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.yield(finalResponse)
                    progress.markToken()
                } else if let missingTail = missingStreamTail(from: finalResponse, streamed: streamed),
                          !missingTail.isEmpty {
                    continuation.yield(missingTail)
                    progress.markToken()
                }
            }

            if !progress.hasEmittedToken() {
                await MainActor.run { [weak self] in
                    self?.generationError = "Model produced no output. The model may need to be reloaded."
                }
                AppLogger.warning("Generation completed but no tokens were emitted", category: .inference)
            }
        }
        
        return stream
    }
    
    // Returns true if reload was successful
    func reloadCurrentModel() async -> Bool {
        guard let path = modelPath else { return false }
        let url = URL(fileURLWithPath: path)
        AppLogger.info("Reloading model to recover from error...", category: .model)
        do {
            try await loadModel(at: url)
            return true
        } catch {
            AppLogger.error("Failed to auto-reload model: \(error)", category: .model)
            return false
        }
    }

    func stopGeneration() {
        llm?.stop()
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        generationError = nil
        lastGenerationWasCancelled = true
    }

    func unloadModel() {
        stopGeneration()
        llm = nil
        modelPath = nil
        isLoaded = false
        isLoadingModel = false
        loadError = nil
        generationError = nil
        modelWarnings = []
        AppLogger.info("Model unloaded.", category: .model)
    }

    private func applySamplingPreset(_ preset: SamplingPreset, to llm: LLM) {
        let resolved = resolvedSampling(from: preset)
        llm.topK = Int32(max(1, resolved.topK))
        llm.topP = Float(resolved.topP)
        llm.temp = Float(max(0.0, resolved.temperature))
        llm.repeatPenalty = Float(resolved.repeatPenalty)
    }

    private func resolvedSampling(from base: SamplingPreset) -> SamplingPreset {
        let defaults = UserDefaults.standard
        let temperature = (defaults.object(forKey: samplingTemperatureDefaultsKey) as? NSNumber)?.doubleValue ?? base.temperature
        let topKValue = (defaults.object(forKey: samplingTopKDefaultsKey) as? NSNumber)?.intValue ?? base.topK
        let repeatPenalty = (defaults.object(forKey: samplingRepeatPenaltyDefaultsKey) as? NSNumber)?.doubleValue ?? base.repeatPenalty

        return SamplingPreset(
            temperature: min(max(temperature, 0.0), 1.5),
            topK: min(max(topKValue, 1), 200),
            topP: base.topP,
            repeatPenalty: min(max(repeatPenalty, 0.8), 1.5)
        )
    }

    private func trimmedHistory(_ messages: [ChatMessage]) -> [ChatMessage] {
        var included: [ChatMessage] = []
        var characterBudget = 0

        for message in messages.reversed().prefix(maxHistoryMessages) {
            let next = message.content.count
            if characterBudget + next > maxPromptCharacters {
                break
            }
            characterBudget += next
            included.append(message)
        }

        return included.reversed()
    }

    private func systemPromptForCurrentStyle(override: String) -> String {
        if !override.isEmpty {
            return override
        }

        let style = UserDefaults.standard.string(forKey: responseStyleDefaultsKey) ?? "auto"
        let useThinkingTags: Bool = {
            switch style {
            case "thinking":
                return true
            case "instruct":
                return false
            case "auto":
                if let modelPath {
                    let lower = modelPath.lowercased()
                    if lower.contains("thinking") { return true }
                    if lower.contains("instruct") { return false }
                }
                return activeProfile == .qwen3
            default:
                return false
            }
        }()

        let identity = "You are EliAI, a helpful AI assistant running locally on this device."

        let format = """
        Respond in clear Markdown. Use LaTeX for math: inline $...$ and display $$...$$.
        If required information is missing, ask one concise question before proceeding.
        """

        let thinking = useThinkingTags
            ? "For complex questions, think step-by-step inside <think>...</think> tags before giving your final answer."
            : ""

        let tools = """
        You have tools for files, memory, and tasks. When asked to perform these actions, call a tool — never describe what you would do instead.

        To call a tool, output:
        <tool_call>
        {"name": "TOOL_NAME", "arguments": {"key": "value"}}
        </tool_call>

        Tools:
        - create_file(path, content) — create or overwrite a file
        - read_file(path) — read file contents
        - list_files(directory) — list files; omit directory for root
        - create_memory(title, content) — save a persistent note
        - create_task(title, due?, details?) — create a task

        Never fabricate file contents, directory listings, or tool errors. Only report what tool output actually returns.
        """

        return [identity, format, thinking, tools]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func missingStreamTail(from final: String, streamed: String) -> String? {
        guard !final.isEmpty else { return nil }
        guard !streamed.isEmpty else { return final }
        if final == streamed {
            return nil
        }
        if final.hasPrefix(streamed) {
            let start = final.index(final.startIndex, offsetBy: streamed.count)
            return String(final[start...])
        }
        return nil
    }

    private func extractStringResponse(from value: Any) -> String? {
        if let stringValue = value as? String {
            return stringValue
        }

        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional, let child = mirror.children.first else {
            return nil
        }

        return extractStringResponse(from: child.value)
    }
}
