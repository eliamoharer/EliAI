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
            var accumulatedResponse = ""  // Buffer to catch the full response
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
            
            // Get the full response from the model
            let responseAny: Any = await llm.respond(to: prompt)
            llm.update = { _ in }

            if Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.lastGenerationWasCancelled = true
                }
                return
            }

            // If we already emitted tokens but also have a response object, we're done
            if emittedAnyToken {
                return
            }

            // Try to extract and emit response from various possible formats
            var extractedContent: String?
            
            if let fullResponse = responseAny as? String {
                extractedContent = fullResponse
            } else if let stringResponse = extractStringResponse(from: responseAny) {
                extractedContent = stringResponse
            }
            
            if let content = extractedContent {
                let cleaned = content
                    .replacingOccurrences(of: "<|im_end|>", with: "")
                    .replacingOccurrences(of: "<|endoftext|>", with: "")
                    .replacingOccurrences(of: "<|assistant|>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleaned.isEmpty {
                    emittedAnyToken = true
                    continuation.yield(cleaned)
                    return
                }
            }

            // If we still haven't emitted anything, it's an error
            if !emittedAnyToken {
                await MainActor.run { [weak self] in
                    self?.generationError = "The model returned an empty response. This may indicate the model needs to be reloaded."
                }
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

        let tools = """
        TOOL USE INSTRUCTIONS:
        To use a tool, you MUST output a JSON object wrapped in <tool_call> tags. Follow this EXACT format:
        
        <tool_call>
        {
          "name": "create_file",
          "arguments": {
            "path": "notes/example.txt",
            "content": "The exact content to write to the file"
          }
        }
        </tool_call>
        
        CRITICAL RULES:
        1. The "arguments" field must contain ALL the actual values - NEVER use placeholder text like "Hello world" unless that's what the user asked for
        2. Use the EXACT content the user requested - if user says "write a summary about X", write the actual summary, not "Hello world"
        3. ALWAYS close the </tool_call> tag properly
        4. Valid JSON only - no comments, no trailing commas
        
        Available Tools:
        - create_file(path: String, content: String) - Creates a new file with the specified content
        - read_file(path: String) - Reads the contents of a file
        - list_files(directory: String) - Lists files in a directory
        - create_memory(title: String, content: String) - Creates a memory note
        - create_task(title: String, due: String?, details: String?) - Creates a task
        
        You have full file system access. Use tools when the user asks for file operations.
        """

        func getBasePrompt() -> String {
            let style = UserDefaults.standard.string(forKey: responseStyleDefaultsKey) ?? "auto"
            switch style {
            case "instruct":
                return "You are EliAI, an intelligent and helpful assistant. You can have natural conversations. You have full file system access via tools. Only use tools if the user explicitly asks for a file or task operation."
            case "thinking":
                return "You are EliAI, an intelligent and helpful assistant. You can have natural conversations. If you provide reasoning, place it inside <think>...</think>. You have full file system access via tools. Only use tools if the user explicitly asks for a file or task operation."
            case "auto":
                if let modelPath {
                    let lower = modelPath.lowercased()
                    if lower.contains("thinking") {
                        return "You are EliAI, an intelligent and helpful assistant. You can have natural conversations. If you provide reasoning, place it inside <think>...</think>. You have full file system access via tools. Only use tools if the user explicitly asks for a file or task operation."
                    }
                    if lower.contains("instruct") {
                        return "You are EliAI, an intelligent and helpful assistant. You can have natural conversations. You have full file system access via tools. Only use tools if the user explicitly asks for a file or task operation."
                    }
                }
                
                switch activeProfile {
                case .qwen3:
                    return "You are EliAI, an intelligent and helpful assistant. You can have natural conversations. If you provide reasoning, place it inside <think>...</think>. You have full file system access via tools. Only use tools if the user explicitly asks for a file or task operation."
                case .lfm25, .generic:
                    return "You are EliAI, an intelligent and helpful assistant. You can have natural conversations. You have full file system access via tools. Only use tools if the user explicitly asks for a file or task operation."
                }
            default:
                return "You are EliAI, an intelligent and helpful assistant that can manage files, tasks, and memories. You can also chat naturally. You have full file system access via tools."
            }
        }
        
        return getBasePrompt() + "\n\n" + tools
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
