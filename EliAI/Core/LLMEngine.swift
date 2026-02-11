import Foundation

// MARK: - LLM Engine
// Wraps llama.cpp C API via XCFramework for on-device inference

import llama

@Observable
class LLMEngine {
    var isLoaded = false
    var isGenerating = false
    var loadingProgress: String = ""
    var tokensPerSecond: Double = 0

    private var model: OpaquePointer?     // llama_model *
    private var context: OpaquePointer?   // llama_context *
    private var sampler: OpaquePointer?   // llama_sampler *
    private var currentTokenCount: Int32 = 0

    // Settings
    var temperature: Float = 0.7
    var topP: Float = 0.9
    var topK: Int32 = 40
    var maxTokens: Int32 = 512
    var contextSize: Int32 = 2048
    var repeatPenalty: Float = 1.1

    deinit {
        unloadModel()
    }

    // MARK: - Model Loading

    func loadModel(at path: URL) async throws {
        guard !isLoaded else { return }

        loadingProgress = "Initializing backend..."
        llama_backend_init()

        loadingProgress = "Loading model..."

        // Model params — use Metal for GPU acceleration on iOS
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99  // Offload all layers to GPU (Metal)

        guard let loadedModel = llama_model_load_from_file(path.path, modelParams) else {
            throw LLMError.modelLoadFailed("Failed to load model from \(path.lastPathComponent)")
        }
        self.model = loadedModel

        loadingProgress = "Creating context..."

        // Context params
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextSize)
        ctxParams.n_batch = 512
        ctxParams.n_threads = UInt32(ProcessInfo.processInfo.activeProcessorCount)
        ctxParams.n_threads_batch = UInt32(ProcessInfo.processInfo.activeProcessorCount)

        guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            self.model = nil
            throw LLMError.contextCreationFailed
        }
        self.context = ctx

        // Create sampler chain
        setupSampler()

        isLoaded = true
        loadingProgress = "Ready"
    }

    func unloadModel() {
        if let sampler = sampler {
            llama_sampler_free(sampler)
            self.sampler = nil
        }
        if let context = context {
            llama_free(context)
            self.context = nil
        }
        if let model = model {
            llama_model_free(model)
            self.model = nil
        }
        isLoaded = false
        currentTokenCount = 0
        loadingProgress = ""
    }

    // MARK: - Sampler Setup

    private func setupSampler() {
        if let existing = sampler {
            llama_sampler_free(existing)
        }

        let chainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(chainParams) else { return }

        // Add samplers in order
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(0))

        self.sampler = chain
    }

    // MARK: - Text Generation

    func generate(messages: [ChatMessage]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                await MainActor.run { self.isGenerating = true }

                do {
                    // Format messages into ChatML prompt
                    let prompt = self.formatChatML(messages: messages)

                    // Tokenize
                    let tokens = try self.tokenize(text: prompt, addBOS: true)

                    // Clear KV cache for fresh generation
                    if let ctx = self.context {
                        llama_kv_cache_clear(ctx)
                    }

                    // Process prompt tokens
                    try self.processPromptTokens(tokens)

                    // Generate tokens
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var generatedCount: Int32 = 0
                    self.currentTokenCount = Int32(tokens.count)

                    while generatedCount < self.maxTokens {
                        guard let sampler = self.sampler,
                              let ctx = self.context else { break }

                        // Sample next token
                        let newToken = llama_sampler_sample(sampler, ctx, -1)

                        // Check for EOS
                        guard let model = self.model else { break }
                        if llama_token_is_eog(model, newToken) {
                            break
                        }

                        // Convert token to text
                        let piece = self.tokenToString(newToken)
                        if !piece.isEmpty {
                            continuation.yield(piece)
                        }

                        // Prepare next decode step
                        let batch = llama_batch_get_one(&[newToken], 1)
                        let result = llama_decode(ctx, batch)
                        if result != 0 {
                            break
                        }

                        generatedCount += 1
                        self.currentTokenCount += 1

                        // Update tokens/second
                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed > 0 {
                            await MainActor.run {
                                self.tokensPerSecond = Double(generatedCount) / elapsed
                            }
                        }
                    }
                } catch {
                    continuation.yield("\n[Error: \(error.localizedDescription)]")
                }

                await MainActor.run { self.isGenerating = false }
                continuation.finish()
            }
        }
    }

    // MARK: - ChatML Formatting

    func formatChatML(messages: [ChatMessage]) -> String {
        var prompt = ""
        for message in messages {
            let role: String
            switch message.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            case .tool: role = "system"
            }
            prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
        }
        // Add assistant prefix to begin generation
        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    // MARK: - Tokenization

    private func tokenize(text: String, addBOS: Bool) throws -> [llama_token] {
        guard let model = model else {
            throw LLMError.modelNotLoaded
        }

        let utf8Text = text.utf8CString
        let maxTokens = Int32(utf8Text.count) + 128

        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = utf8Text.withUnsafeBufferPointer { buf in
            llama_tokenize(model, buf.baseAddress, Int32(text.utf8.count), &tokens, maxTokens, addBOS, true)
        }

        guard nTokens >= 0 else {
            throw LLMError.tokenizationFailed
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    private func tokenToString(_ token: llama_token) -> String {
        guard let model = model else { return "" }
        var buf = [CChar](repeating: 0, count: 256)
        let nBytes = llama_token_to_piece(model, token, &buf, 256, 0, false)
        if nBytes > 0 {
            return String(cString: buf)
        }
        return ""
    }

    // MARK: - Prompt Processing

    private func processPromptTokens(_ tokens: [llama_token]) throws {
        guard let ctx = context else {
            throw LLMError.modelNotLoaded
        }

        // Process in batches
        let batchSize = 512
        var pos = 0

        while pos < tokens.count {
            let end = min(pos + batchSize, tokens.count)
            var batchTokens = Array(tokens[pos..<end])
            let batch = llama_batch_get_one(&batchTokens, Int32(batchTokens.count))

            let result = llama_decode(ctx, batch)
            if result != 0 {
                throw LLMError.decodeFailed(result)
            }

            pos = end
        }
    }

    // MARK: - Context Management

    func resetContext() {
        if let ctx = context {
            llama_kv_cache_clear(ctx)
        }
        currentTokenCount = 0
    }

    var contextUsage: Float {
        guard isLoaded else { return 0 }
        return Float(currentTokenCount) / Float(contextSize)
    }

    func updateSamplerSettings(temp: Float, topP: Float, topK: Int32) {
        self.temperature = temp
        self.topP = topP
        self.topK = topK
        setupSampler()
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case contextCreationFailed
    case tokenizationFailed
    case decodeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Model is not loaded"
        case .modelLoadFailed(let msg): return "Failed to load model: \(msg)"
        case .contextCreationFailed: return "Failed to create inference context"
        case .tokenizationFailed: return "Failed to tokenize input"
        case .decodeFailed(let code): return "Decode failed with code \(code)"
        }
    }
}
