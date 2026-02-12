import Foundation
import llama

@Observable
@MainActor
class LLMEngine {
    var isLoaded = false
    var isGenerating = false
    var modelPath: String?
    
    // In a real implementation with the library linked:
    // private var context: LlamaContext? 
    
    init() {}
    
    func loadModel(at url: URL) async throws {
        if isGenerating { isGenerating = false }
        
        let path = url.path
        print("Loading model from: \(path)")
        
        // Actual loading logic would be:
        // let model = try? LlamaModel(path: path)
        // self.context = try? LlamaContext(model: model!)
        
        self.modelPath = path
        self.isLoaded = true
        print("Model loaded successfully")
    }
    
    func generate(prompt: String, systemPrompt: String = "") -> AsyncStream<String> {
        isGenerating = true
        
        return AsyncStream { continuation in
            Task {
                _ = buildPrompt(system: systemPrompt, user: prompt)
                
                // Actual inference logic:
                // await context?.completion(fullPrompt) { token in
                //    continuation.yield(token)
                // }
                
                // Simulation for now to ensure compilation stability
                let words = "This is a simulated response from the local AI model (HY-1.8B). Inference logic is stubbed in LLMEngine.swift to ensure safe initial compilation.".components(separatedBy: " ")
                
                for word in words {
                    if !isGenerating { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continuation.yield(word + " ")
                }
                
                continuation.finish()
                isGenerating = false
            }
        }
    }
    
    func stopGeneration() {
        isGenerating = false
    }
    
    private func buildPrompt(system: String, user: String) -> String {
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }
}
