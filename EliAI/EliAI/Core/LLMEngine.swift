import Foundation
import llama

@Observable
@MainActor
class LLMEngine {
    var isLoaded = false
    var isGenerating = false
    var modelPath: String?
    var loadError: String?
    
    // Correctly declare the context
    private var context: LlamaContext? 
    
    init() {}
    
    func loadModel(at url: URL) async throws {
        if isGenerating { isGenerating = false }
        self.loadError = nil
        
        let path = url.path
        print("Loading model from: \(path)")
        
        do {
            let model = try LlamaModel(path: path)
            self.context = try LlamaContext(model: model)
            
            self.modelPath = path
            self.isLoaded = true
            print("Model loaded successfully")
        } catch {
            self.loadError = error.localizedDescription
            self.isLoaded = false
            print("Model loading failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func generate(prompt: String, systemPrompt: String = "") -> AsyncStream<String> {
        isGenerating = true
        
        return AsyncStream { continuation in
            Task {
                let fullPrompt = buildPrompt(system: systemPrompt, user: prompt)
                
                // Real inference logic
                if let context = self.context {
                    await context.completion(fullPrompt) { token in
                        continuation.yield(token)
                    }
                } else {
                    continuation.yield("Error: Model context not initialized.")
                }
                
                continuation.finish()
                isGenerating = false
            }
        }
    }
    
    func stopGeneration() {
        isGenerating = false
        // Implementing stop logic might require context cancellation if supported
    }
    
    private func buildPrompt(system: String, user: String) -> String {
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }
}
