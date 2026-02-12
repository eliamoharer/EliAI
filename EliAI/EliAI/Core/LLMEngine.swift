import Foundation
import LLM

@Observable
@MainActor
class LLMEngine {
    var isLoaded = false
    var isGenerating = false
    var modelPath: String?
    var loadError: String?
    
    // State-of-the-Art 2026 LLM Interface
    private var llm: LLM?
    private var generationTask: Task<Void, Never>?
    
    init() {}
    
    func loadModel(at url: URL) async throws {
        if isGenerating { isGenerating = false }
        self.loadError = nil
        
        let path = url.path
        print("Loading model via LLM.swift from: \(path)")
        
        // LLM.swift handles the heavy lifting of backend init & Metal acceleration
        do {
            let modelURL = URL(fileURLWithPath: path)
            let loadedLLM = try await LLM(from: modelURL, template: .none)
            
            self.llm = loadedLLM
            self.modelPath = path
            self.isLoaded = true
            print("Model loaded successfully with LLM.swift")
        } catch {
            self.loadError = "Library could not parse model (2026 Backend Error): \(error.localizedDescription)"
            self.isLoaded = false
            print("Model loading failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func generate(prompt: String, systemPrompt: String = "") -> AsyncStream<String> {
        generationTask?.cancel() 
        isGenerating = true
        
        return AsyncStream { continuation in
            generationTask = Task.detached(priority: .userInitiated) { [weak self] in
                // Thread-safe state capture (2026 Standard)
                guard let self = self, 
                      let (llm, path) = await MainActor.run(resultType: (LLM, String)?.self, body: {
                          guard let engineLLM = self.llm else { return nil }
                          return (engineLLM, self.modelPath?.lowercased() ?? "")
                      }) else {
                    continuation.yield("Error: LLM Engine not ready.")
                    continuation.finish()
                    return
                }
                
                // Detection logic with Qwen 3 as the absolute default/fallback
                if path.contains("lfm") {
                    await MainActor.run {
                        llm.temperature = 0.1
                        llm.topP = 0.1
                        llm.repeatPenalty = 1.05
                        print("Applied LFM 2.5 Sampling Standards")
                    }
                } else {
                    await MainActor.run {
                        llm.temperature = 0.7
                        llm.topP = 0.8
                        llm.repeatPenalty = 1.1
                        print("Applied Qwen 3 Sampling Standards")
                    }
                }
                
                // Stream using 2026 native high-level API
                do {
                    await llm.resetContext()
                    
                    // Qwen 3 / ChatML Formatting
                    let formattedPrompt = "<|im_start|>system\n\(systemPrompt.isEmpty ? "You are EliAI, a helpful assistant." : systemPrompt)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
                    
                    for try await token in llm.generate(formattedPrompt) {
                        if Task.isCancelled { break }
                        if token.contains("<|im_end|>") { break }
                        continuation.yield(token)
                    }
                } catch {
                    continuation.yield("Error during generation: \(error.localizedDescription)")
                }
                
                await MainActor.run { self.isGenerating = false }
                continuation.finish()
            }
        }
    }
    
    func stopGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }
    
    func unloadModel() {
        stopGeneration()
        self.llm = nil
        self.modelPath = nil
        self.isLoaded = false
        self.loadError = nil
    }
}
