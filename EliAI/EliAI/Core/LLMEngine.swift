import Foundation
import Observation
import UIKit
@preconcurrency import LLM

enum LLMEngineError: LocalizedError {
    case modelLoadTimeout(seconds: Int)

    var errorDescription: String? {
        switch self {
        case let .modelLoadTimeout(seconds):
            return "Model loading exceeded \(seconds) seconds and was cancelled."
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
    private var memoryWarningObserver: NSObjectProtocol?

    private let maxPromptCharacters = 24_000
    private let maxHistoryMessages = 24
    private let loadTimeoutSeconds = 120

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

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
            let loadTask = Task {
                try await LLM(from: modelURL, template: .none)
            }

            let timeoutTask = Task {
                let timeoutNanos = UInt64(loadTimeoutSeconds) * 1_000_000_000
                try await Task.sleep(nanoseconds: timeoutNanos)
                loadTask.cancel()
            }

            let loadedLLM: LLM
            do {
                loadedLLM = try await loadTask.value
                timeoutTask.cancel()
            } catch is CancellationError {
                timeoutTask.cancel()
                throw LLMEngineError.modelLoadTimeout(seconds: loadTimeoutSeconds)
            } catch {
                timeoutTask.cancel()
                throw error
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

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
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
                    await llm.resetContext()

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

    private func handleMemoryWarning() {
        AppLogger.warning("Memory warning received. Cancelling generation and clearing state.", category: .inference)
        stopGeneration()
    }

    private func applySamplingPreset(_ preset: SamplingPreset, to llm: LLM) {
        llm.temperature = preset.temperature
        llm.topP = preset.topP
        llm.repeatPenalty = preset.repeatPenalty
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
}
