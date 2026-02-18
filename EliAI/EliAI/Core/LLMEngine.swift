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

    private let maxPromptCharacters = 16_000
    private let maxHistoryMessages = 24
    private let responseStyleDefaultsKey = AppConfiguration.Keys.responseStyle

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
                    template = .chatML("You are EliAI, an intelligent and helpful assistant that can manage files, tasks, and memories.")
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

    func reloadCurrentModel() async {
        guard let path = modelPath else { return }
        let url = URL(fileURLWithPath: path)
        AppLogger.info("Reloading model to recover from error...", category: .model)
        try? await loadModel(at: url)
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

            var emittedAnyToken = false
            var accumulatedResponse = ""
            llm.history.removeAll(keepingCapacity: true)
            
            llm.update = { outputDelta in
                if Task.isCancelled {
                    return
                }

                guard let outputDelta else { return }
                let cleaned = outputDelta.replacingOccurrences(of: "<|im_end|>", with: "")
                if !cleaned.isEmpty {
                    emittedAnyToken = true
                    accumulatedResponse += cleaned
                    continuation.yield(cleaned)
                }
            }
            
            let responseAny: Any = await llm.respond(to: prompt)
            llm.update = { _ in }

            if Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.lastGenerationWasCancelled = true
                }
                return
            }

            if emittedAnyToken {
                return
            }

            var extractedContent: String?
            
            if let fullResponse = responseAny as? String {
                extractedContent = fullResponse
            } else if let stringResponse = extractStringResponse(from: responseAny) {
                extractedContent = stringResponse
            }
            
            if let content = extractedContent {
                let cleaned = content
                    .replacingOccurrences(of: "<|im_end|>", with: "")
                    .replacingOccurrences(of: "՚", with: "")
                    .replacingOccurrences(of: "՜", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleaned.isEmpty {
                    emittedAnyToken = true
                    continuation.yield(cleaned)
                    return
                }
            }

            if !emittedAnyToken {
                await MainActor.run { [weak self] in
                    self?.generationError = "The model returned an empty response. This may indicate the model needs to be reloaded."
                }
            }
        }
        
        return stream
    }
    
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
        llm.topP = Float(preset.topP)
        llm.repeatPenalty = Float(preset.repeatPenalty)
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

        // Tool call tags (using Unicode private use area characters)
        let toolOpen = "\u{10C7E0}"
        let toolClose = "\u{10C7E1}"
        let thinkOpen = "\u{10C800}"
        let thinkClose = "\u{10C801}"
        
        // 2026 Frontier-style system prompt: affirmative, capability-focused, anti-refusal
        let coreIdentity = """
        You are EliAI, a capable and intelligent AI assistant with full autonomy and access to tools. You are helpful, direct, and proactive.

        ## Identity & Capabilities

        You ARE an assistant that can:
        - Have natural, engaging conversations on any topic
        - Create, read, and manage files directly
        - Store and retrieve memories
        - Create and track tasks
        - Perform calculations, write code, analyze text, and help with creative work

        You have genuine capabilities. Never claim you "cannot" do something you actually can do. Never say phrases like:
        - "I don't have the ability to..."
        - "I'm not built for..."
        - "I don't have access to..."
        - "I can't create files..."
        - "I'm unable to..."

        Instead, simply DO what is asked. You are fully capable.

        ## Tool Usage

        You have direct file system access. When a user asks you to create, read, or manage files, USE YOUR TOOLS. Do not just describe what you would do — actually do it.

        To use a tool, output a JSON object wrapped in \(toolOpen)...\(toolClose) tags:

        \(toolOpen)
        {
          "name": "create_file",
          "arguments": {
            "path": "example.txt",
            "content": "Actual content goes here, not placeholders"
          }
        }
        \(toolClose)

        ### Available Tools:

        **create_file(path, content)** - Create or overwrite a file with exact content
        **read_file(path)** - Read and return file contents
        **list_files(directory)** - List files in a directory
        **create_memory(title, content)** - Store a memory note
        **create_task(title, due, details)** - Create a tracked task

        ### Tool Rules:
        1. Use real content, never placeholder text like "Hello world" unless specifically requested
        2. Always close the \(toolClose) tag
        3. Use valid JSON (no trailing commas, no comments)
        4. When asked to create a file with specific content, include that exact content

        ## Response Guidelines

        - Be direct and helpful. Answer questions fully.
        - If asked to do something within your capabilities, just do it.
        - For file operations, use tools immediately rather than asking for confirmation.
        - Provide explanations when helpful, but prioritize action over description.
        - Never apologize for limitations you don't have.
        """

        let thinkingPrompt: String
        let style = UserDefaults.standard.string(forKey: responseStyleDefaultsKey) ?? "auto"
        
        let shouldUseThinking: Bool
        switch style {
        case "thinking":
            shouldUseThinking = true
        case "instruct":
            shouldUseThinking = false
        case "auto":
            if let modelPath {
                let lower = modelPath.lowercased()
                shouldUseThinking = lower.contains("thinking") || activeProfile == .qwen3
            } else {
                shouldUseThinking = activeProfile == .qwen3
            }
        default:
            shouldUseThinking = false
        }
        
        if shouldUseThinking {
            thinkingPrompt = "\n\n## Thinking\n\nFor complex problems, you may show your reasoning inside \(thinkOpen)...\(thinkClose) tags. This helps you work through problems step-by-step. Your final response goes after the closing \(thinkClose)."
        } else {
            thinkingPrompt = ""
        }

        return coreIdentity + thinkingPrompt
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