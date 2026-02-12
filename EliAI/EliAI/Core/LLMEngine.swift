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
            let loadedLLM = try await LLM(from: modelURL, template: .qwen)
            
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
                guard let self = self, let llm = await MainActor.run(resultType: LLM?.self, body: { self.llm }) else {
                    continuation.yield("Error: LLM Engine not ready.")
                    continuation.finish()
                    return
                }
                
                // Apply 2026 Standard Sampling (Prevents looping & nonsense)
                // For Qwen 3 (Flagship): top_p 0.8, repetition_penalty 1.1
                // For LFM 2.5 (Liquid): temp 0.1, top_p 0.1, repetition_penalty 1.05
                
                // applySamplingParameters(llm) 
                let path = await MainActor.run { self.modelPath?.lowercased() ?? "" }
                
                // Detection logic with Qwen 3 as the absolute default/fallback
                if path.contains("lfm") {
                    await MainActor.run {
                        llm.temperature = 0.1
                        llm.topP = 0.1
                        llm.repeatPenalty = 1.05
                        print("Applied LFM 2.5 Sampling Standards")
                    }
                } else {
                    // Qwen 3 Defaults (Golden Standards) - Used as fallback for all other models
                    await MainActor.run {
                        llm.temperature = 0.7
                        llm.topP = 0.8
                        llm.repeatPenalty = 1.1
                        print("Applied Qwen 3 Sampling Standards (Default/Fallback)")
                    }
                }
                
                // Stream using 2026 native high-level API
                do {
                    // Qwen 3 / ChatML Formatting
                    let formattedPrompt = "<|im_start|>system\n\(systemPrompt.isEmpty ? "You are EliAI, a helpful assistant." : systemPrompt)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
                    
                    for try await token in llm.generate(formattedPrompt) {
                        if Task.isCancelled { break }
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
}
