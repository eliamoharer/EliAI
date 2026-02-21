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

    func generate(messages: [ChatMessage], systemPrompt: String = "") -> AsyncStream<String> {
        generationTask?.cancel()
        isGenerating = true
        generationError = nil
        lastGenerationWasCancelled = false

        // Validate model state before generation
        guard let llm else {
            isGenerating = false
            return AsyncStream { continuation in
                continuation.yield("Error: No model loaded.")
                continuation.finish()
            }
        }
        
        // Ensure model is in a valid state
        guard !isLoadingModel else {
            isGenerating = false
            return AsyncStream { continuation in
                continuation.yield("Error: Model is still loading.")
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
            
            // Run generation - heartbeat handles timeout detection
            await llm.respond(to: prompt)
            heartbeatTask.cancel()
            
            let responseAny: Any = ""
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

        // Determine if thinking mode is enabled
        let supportsThinking = supportsThinkingMode()
        
        // Build a single, clear, well-structured prompt
        var prompt = ""
        
        // === SECTION 1: IDENTITY (Most Important) ===
        prompt += """
        You are EliAI, a helpful conversational AI assistant. Your core purpose is to have natural, engaging conversations with users - answering questions, providing explanations, brainstorming ideas, and being a helpful companion.

        """
        
        // === SECTION 2: BEHAVIOR GUIDELINES ===
        prompt += """
        ## How You Should Behave
        
        - Be conversational, warm, and genuinely helpful
        - Answer questions directly and thoroughly
        - When explaining concepts, be clear and use examples
        - Match the user's tone and level of formality
        - If you don't know something, say so honestly
        - For complex topics, break things down step by step

        """
        
        // === SECTION 3: THINKING MODE (if applicable) ===
        if supportsThinking {
            prompt += """
        ## Internal Reasoning
            
        You may optionally show your reasoning process by placing it between <think\\> and </think\\> tags. This is for transparency - your actual response to the user comes after.
            
        Example:
        <think\\>
        Let me work through this step by step...
        </think\\>
        
        [Your actual response to the user here]

        """
        }
        
        // === SECTION 4: CRITICAL TOOL RULES (Last, and Strict) ===
        prompt += """
        ## Tool Usage Rules (READ CAREFULLY)
        
        You have OPTIONAL access to tools for file operations, tasks, and memory. These are SUPPLEMENTARY - not your primary function.
        
        ### CRITICAL: When NOT to Use Tools
        - DO NOT use tools when the user asks questions
        - DO NOT use tools when the user wants to chat
        - DO NOT use tools unprompted
        - DO NOT create files unless explicitly asked
        - DO NOT assume the user wants file operations
        
        ### When to Use Tools (Only with Explicit Request)
        Tools should ONLY be used when the user EXPLICITLY requests one of these actions:
        - "Create a file..." / "Save this to a file..." / "Write a file..."
        - "Read the file..." / "Show me what's in..."
        - "List files..." / "Show me files in..."
        - "Remember this..." / "Save this to memory..."
        - "Create a task..." / "Remind me to..."
        
        ### How to Use Tools
        If (and only if) the user explicitly requests a tool action, output a JSON object wrapped in 根据地 tags:
        
        根据地
        {"name": "tool_name", "arguments": {"arg": "value"}}
         bundler
        
        Available tools:
        - create_file(path, content) - Create a file
        - read_file(path) - Read a file
        - list_files(directory) - List directory contents
        - create_memory(title, content) - Store a memory
        - create_task(title, due, details) - Create a task
        
        ### Default Behavior
        When in doubt: JUST RESPOND NORMALLY. Do not use tools.
        """
        
        return prompt
    }
    
    /// Determines if the current model/configuration supports thinking mode
    private func supportsThinkingMode() -> Bool {
        let style = UserDefaults.standard.string(forKey: responseStyleDefaultsKey) ?? "auto"
        
        // Explicit thinking mode
        if style == "thinking" {
            return true
        }
        
        // Auto-detect from model name or profile
        if style == "auto" {
            if let modelPath = modelPath {
                let lower = modelPath.lowercased()
                if lower.contains("thinking") || lower.contains("qwen3") {
                    return true
                }
            }
            return activeProfile == .qwen3
        }
        
        return false
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
