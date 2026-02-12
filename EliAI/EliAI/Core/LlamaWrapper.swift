import Foundation
import llama

// Define the classes expected by LLMEngine

class LlamaModel {
    var model: OpaquePointer?
    
    init(path: String) throws {
        llama_backend_init()
        var header = llama_model_default_params()
        
        // Critical: Set n_gpu_layers to 0 to prevent crashes from missing Metal resources
        // Once we confirm CPU works, we can look into bundling ggml-metal.metal
        header.n_gpu_layers = 0 
        
        print("LlamaWrapper: Attempting to load model from \(path)")
        
        // Use explicit C-string handling for safety
        self.model = path.withCString { cPath in
            return llama_load_model_from_file(cPath, header)
        }
        
        if self.model == nil {
            print("LlamaWrapper: Failed to load model. Check path, permissions, or corruption.")
            throw NSError(domain: "LlamaError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load model at \(path)"])
        }
        print("LlamaWrapper: Model loaded successfully.")
    }
    
    deinit {
        if let model = model {
            llama_free_model(model)
        }
    }
}

class LlamaContext {
    var context: OpaquePointer?
    var model: LlamaModel
    var batch: llama_batch
    
    init(model: LlamaModel) throws {
        self.model = model
        
        // Context params
        var params = llama_context_default_params()
        params.n_ctx = 2048 // Default context size
        
        self.context = llama_new_context_with_model(model.model, params)
        
        if self.context == nil {
            throw NSError(domain: "LlamaError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
        
        // Initialize batch
        self.batch = llama_batch_init(512, 0, 1)
    }
    
    deinit {
        llama_batch_free(batch)
        if let context = context {
            llama_free(context)
        }
    }
    
    // Simple greedy generation for now
    func completion(_ prompt: String, onToken: (String) -> Void) async {
        guard let ctx = context, let mdl = model.model else { return }
        
        // 1. Tokenize prompt
        let tokens = tokenize(text: prompt, addBos: true)
        if tokens.isEmpty { return }
        
        // 2. Evaluate prompt
        batch.n_tokens = Int32(tokens.count)
        
        for i in 0..<tokens.count {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0 // False
        }
        // Enable logits for the last token to sample next
        batch.logits[tokens.count - 1] = 1 // True
        
        if llama_decode(ctx, batch) != 0 {
            print("llama_decode failed")
            return
        }
        
        var n_cur = batch.n_tokens
        
        // 3. Generation loop
        // We'll generate up to 100 tokens or until EOS
        for _ in 0..<100 {
            // Sample
            let n_vocab = llama_n_vocab(mdl)
            let logits = llama_get_logits_ith(ctx, batch.n_tokens - 1)
            
            // Greedy sampling (argmax)
            var max_logit = -Float.infinity
            var best_token_id: llama_token = 0
            
            for id in 0..<n_vocab {
                let logit = logits![Int(id)]
                if logit > max_logit {
                    max_logit = logit
                    best_token_id = id
                }
            }
            
            // Check EOS
            if best_token_id == llama_token_eos(mdl) {
                break
            }
            
            // Convert to string and yield
            let piece = token_to_piece(token: best_token_id)
            onToken(piece)
            
            // Prepare next batch
            // Reset batch for single token
            batch.n_tokens = 1
            batch.token[0] = best_token_id
            batch.pos[0] = n_cur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1 // True
            
            n_cur += 1
            
            if llama_decode(ctx, batch) != 0 {
                break
            }
            
            // Yield to main loop if needed to keep UI responsive? 
            // We are already in async task.
            await Task.yield() 
        }
    }
    
    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        guard let mdl = model.model else { return [] }
        
        let n_tokens = text.utf8.count + (addBos ? 1 : 0)
        var tokens = [llama_token](repeating: 0, count: n_tokens + 10) // buffer
        
        let n = llama_tokenize(mdl, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), addBos, false)
        
        if n < 0 {
             // Buffer too small, simpler to just return empty or retry with larger buffer
             // For now assume it fits
             return []
        }
        
        return Array(tokens.prefix(Int(n)))
    }
    
    private func token_to_piece(token: llama_token) -> String {
        guard let mdl = model.model else { return "" }
        
        // llama_token_to_piece result length includes null terminator?
        // Let's use a buffer
        var buf = [CChar](repeating: 0, count: 8)
        var n = llama_token_to_piece(mdl, token, &buf, Int32(buf.count), false)
        
        if n < 0 {
            // Buffer too small
            let size = Int(-n)
            buf = [CChar](repeating: 0, count: size)
            n = llama_token_to_piece(mdl, token, &buf, Int32(buf.count), false)
        }
        
        // Remove 'n' from string construction
        return String(cString: buf)
    }
}
