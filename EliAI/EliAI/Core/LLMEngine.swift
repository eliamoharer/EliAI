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

            let modelURL = URL(fileURLWithPath: url.path)
            let template = templateForProfile(validation.profile)
            guard let loadedLLM = LLM(from: modelURL, template: template) else {
                throw LLMEngineError.modelInitializationFailed
            }

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

        return AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            continuation.onTermination = { [weak self] (_: AsyncStream<String>.Continuation.Termination) in
                Task { @MainActor in
                    self?.stopGeneration()
                }
            }

            generationTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.yield("Error: LLM engine is unavailable.")
                    continuation.finish()
                    return
                }

                guard let llm = self.llm else {
                    continuation.yield("Error: No model loaded.")
                    continuation.finish()
                    self.isGenerating = false
                    return
                }

                let profile = self.activeProfile
                let clippedMessages = self.trimmedHistory(messages)
                let prompt = profile.formatPrompt(messages: clippedMessages, systemPrompt: systemPrompt)
                self.applySamplingPreset(profile.sampling, to: llm)

                do {
                    AppLogger.debug("Starting generation with profile \(profile.displayName).", category: .inference)

                    for try await token in llm.generate(prompt) {
                        if Task.isCancelled { break }
                        if token.contains("<|im_end|>") { break }
                        continuation.yield(token)
                    }
                } catch {
                    continuation.yield("Error during generation: \(error.localizedDescription)")
                    self.generationError = error.localizedDescription
                    AppLogger.error("Generation failed: \(error.localizedDescription)", category: .inference)
                }

                self.isGenerating = false
                continuation.finish()
            }
        }
    }

    func stopGeneration() {
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

    private func templateForProfile(_ profile: ModelProfile) -> Template {
        switch profile {
        case .qwen3, .lfm25:
            return .chatML("You are EliAI, an intelligent and helpful assistant that can manage files, tasks, and memories.")
        case .generic:
            return .chatML("You are EliAI, an intelligent and helpful assistant that can manage files, tasks, and memories.")
        }
    }
}
