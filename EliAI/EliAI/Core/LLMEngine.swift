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

    private let maxPromptCharacters = AppConstants.LLMEngine.maxPromptCharacters
    private let maxHistoryMessages = AppConstants.LLMEngine.maxHistoryMessages
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
            var lastTokenTime = Date()
            let timeoutInterval = AppConstants.LLMEngine.generationTimeoutSeconds
            let heartbeatInterval = AppConstants.LLMEngine.streamHeartbeatIntervalSeconds
            
            // Heartbeat task to detect stalled streams
            let heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                    let timeSinceLastToken = Date().timeIntervalSince(lastTokenTime)
                    if timeSinceLastToken > timeoutInterval {
                        await MainActor.run { [weak self] in
                            self?.generationError = "Generation timeout: No response from model"
                        }
                        continuation.finish()
                        return
                    }
                }
            }
            
            llm.history.removeAll(keepingCapacity: true)
            llm.update = { outputDelta in
                if Task.isCancelled {
                    return
                }

                guard let outputDelta else { return }
                let cleaned = outputDelta.replacingOccurrences(of: "<|im_end|>", with: "")
                if !cleaned.isEmpty {
                    emittedAnyToken = true
                    lastTokenTime = Date()
                    continuation.yield(cleaned)
                }
            }
            
            // Run generation with timeout
            let generationTask = Task {
                await llm.respond(to: prompt)
            }
            
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
                generationTask.cancel()
                await MainActor.run { [weak self] in
                    self?.generationError = "Generation timeout: Model took too long to respond"
                }
            }
            
            let responseAny: Any = await generationTask.value
            timeoutTask.cancel()
            heartbeatTask.cancel()
            llm.update = { _ in }

            if Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.lastGenerationWasCancelled = true
                }
                return
            }

            // Try to extract response if no tokens were emitted via callback
            if !emittedAnyToken {
                if let fullResponse = responseAny as? String {
                    let cleanedResponse = fullResponse.replacingOccurrences(of: "<|im_end|>", with: "")
                    if !cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emittedAnyToken = true
                        continuation.yield(cleanedResponse)
                    }
                } else if let optionalStringResponse = extractStringResponse(from: responseAny) {
                    let cleanedResponse = optionalStringResponse.replacingOccurrences(of: "<|im_end|>", with: "")
                    if !cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emittedAnyToken = true
                        continuation.yield(cleanedResponse)
                    }
                }
            }

            if !emittedAnyToken {
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
        Tool Usage:
        To use a tool, output a JSON object wrapped in <tool_call> tags. Example:
        <tool_call>
        {
          "name": "create_file",
          "arguments": {
            "path": "notes/hello.txt",
            "content": "Hello world"
          }
        }
        </tool_call>
        
        Available Tools:
        - create_file(path: String, content: String) - Create a new file
        - read_file(path: String) - Read file contents
        - list_files(directory: String) - List files in a directory
        - create_memory(title: String, content: String) - Store information in memory
        - create_task(title: String, due: String?, details: String?) - Create a task
        
        Use tools ONLY when the user explicitly requests a file operation, task creation, or memory storage. Do not use tools for general conversation or questions.
        """

        func getBasePrompt() -> String {
            let style = UserDefaults.standard.string(forKey: responseStyleDefaultsKey) ?? "auto"
            switch style {
            case "instruct":
                return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
            case "thinking":
                return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nIf you provide reasoning or internal thoughts, place them inside <think>...</think> tags.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
            case "auto":
                if let modelPath {
                    let lower = modelPath.lowercased()
                    if lower.contains("thinking") {
                        return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nIf you provide reasoning or internal thoughts, place them inside <think>...</think> tags.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
                    }
                    if lower.contains("instruct") {
                        return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
                    }
                }
                
                switch activeProfile {
                case .qwen3:
                    return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nIf you provide reasoning or internal thoughts, place them inside <think>...</think> tags.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
                case .lfm25, .generic:
                    return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
                }
            default:
                return "You are EliAI, an intelligent and helpful assistant. Your primary role is to have natural, helpful conversations with users.\n\nYou have access to tools for file operations, task management, and memory storage. These tools should ONLY be used when:\n- The user explicitly requests a file operation (create, read, list files)\n- The user explicitly asks you to create a task or memory\n- The user's request cannot be fulfilled through conversation alone\n\nWhen users ask questions or want to chat, respond naturally without using tools. Only use tools when there's a clear, explicit request for a tool-based action."
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
