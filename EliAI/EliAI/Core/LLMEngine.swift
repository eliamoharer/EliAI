import Foundation
import LlamaSwift

@Observable
@MainActor
class LLMEngine {
    var isLoaded = false
    var isGenerating = false
    var modelPath: String?
    var loadError: String?
    
    // Correctly declare the context and task management
    private var context: LlamaContext? 
    private var generationTask: Task<Void, Never>?
    
    init() {}
    
    func loadModel(at url: URL) async throws {
        if isGenerating { isGenerating = false }
        self.loadError = nil
        
        let path = url.path
        print("Loading model from: \(path)")
        
        // Move to background to avoid blocking the UI thread
        try await Task.detached(priority: .userInitiated) {
            do {
                let model = try LlamaModel(path: path)
                let context = try LlamaContext(model: model)
                
                await MainActor.run {
                    self.context = context
                    self.modelPath = path
                    self.isLoaded = true
                    print("Model loaded successfully")
                }
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.isLoaded = false
                    print("Model loading failed: \(error.localizedDescription)")
                }
                throw error
            }
        }.value
    }
    
    func generate(prompt: String, systemPrompt: String = "") -> AsyncStream<String> {
        generationTask?.cancel() // Cancel any ongoing generation
        isGenerating = true
        
        return AsyncStream { continuation in
            generationTask = Task.detached(priority: .userInitiated) {
                let fullPrompt = await MainActor.run { self.buildPrompt(system: systemPrompt, user: prompt) }
                
                guard let ctx = await MainActor.run(resultType: LlamaContext?.self, body: { self.context }) else {
                    continuation.yield("Error: Model context not initialized.")
                    continuation.finish()
                    return
                }
                
                // Clear KV cache for a fresh conversation session
                ctx.resetContext()
                
                await ctx.completion(fullPrompt) { token in
                    if Task.isCancelled { return }
                    continuation.yield(token)
                }
                
                continuation.finish()
                await MainActor.run { self.isGenerating = false }
            }
            
            continuation.onTermination = { @Sendable _ in
                // Using class level task is not safe here, but we've handled cancellation in the task body
            }
        }
    }
    
    func stopGeneration() {
        isGenerating = false
        // Implementing stop logic might require context cancellation if supported
    }
    
    private func buildPrompt(system: String, user: String) -> String {
        let sys = system.isEmpty ? "You are a helpful assistant." : system
        // Modern ChatML Template (Qwen 3 / Blackwell-ready)
        return "<|im_start|>system\n\(sys)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }
}
