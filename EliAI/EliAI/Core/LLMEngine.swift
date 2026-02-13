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
    var activeProfile: ModelProfile = .generic
    var modelWarnings: [String] = []

    private var llm: LLM?
    private var generationTask: Task<Void, Never>?

    private let maxPromptCharacters = 24_000
    private let maxHistoryMessages = 24
    private let responseStyleDefaultsKey = "responseStyle"

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
            var emittedText = ""
            defer {
                Task { @MainActor [weak self] in
                    self?.isGenerating = false
                    self?.generationTask = nil
                }
                continuation.finish()
            }

            if Task.isCancelled {
                return
            }

            let sanitize: (String) -> String = { text in
                text.replacingOccurrences(of: "<|im_end|>", with: "")
            }

            let finalOutput = await llm.getCompletion(from: prompt, stopSequence: "<|im_end|>") { partial in
                if Task.isCancelled {
                    return false
                }

                let cleanedPartial = sanitize(partial)
                guard cleanedPartial.hasPrefix(emittedText) else {
                    return true
                }

                let delta = String(cleanedPartial.dropFirst(emittedText.count))
                if !delta.isEmpty {
                    continuation.yield(delta)
                    emittedText = cleanedPartial
                }
                return true
            }

            if Task.isCancelled {
                return
            }

            if let finalOutput {
                let cleanedFinal = sanitize(finalOutput)
                if cleanedFinal.hasPrefix(emittedText) {
                    let tail = String(cleanedFinal.dropFirst(emittedText.count))
                    if !tail.isEmpty {
                        continuation.yield(tail)
                    }
                } else if emittedText.isEmpty && !cleanedFinal.isEmpty {
                    continuation.yield(cleanedFinal)
                }
            }
        }

        return stream
    }

    func stopGeneration() {
        llm?.stop()
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
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

        let style = UserDefaults.standard.string(forKey: responseStyleDefaultsKey) ?? "thinking"
        switch style {
        case "instruct":
            return "You are EliAI, an intelligent and helpful assistant for files and tasks. Answer directly and do not output <think> tags."
        case "thinking":
            return "You are EliAI, an intelligent and helpful assistant for files and tasks. If you provide reasoning, place it inside <think>...</think> and then provide the final answer."
        default:
            return "You are EliAI, an intelligent and helpful assistant that can manage files, tasks, and memories."
        }
    }
}
