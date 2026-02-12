import Foundation
import llama

// Define the classes expected by LLMEngine

class LlamaModel {
    var model: OpaquePointer?
    
    // Ensure backend is initialized exactly once
    private static let initializeBackend: Void = {
        print("LlamaWrapper: Initializing generic backend...")
        llama_backend_init()
    }()
    
    init(path: String) throws {
        // Trigger static initialization
        _ = LlamaModel.initializeBackend
        
        print("LlamaWrapper: Checking file at \(path)")
        if !FileManager.default.fileExists(atPath: path) {
            throw NSError(domain: "LlamaError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model file not found at \(path)"])
        }
        
        // 1. Diagnostic magic byte check
        if let fileHandle = FileHandle(forReadingAtPath: path) {
            if let data = try? fileHandle.read(upToCount: 4) {
                let magicBytes = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("LlamaWrapper: File magic bytes: \(magicBytes)")
                
                // GGUF magic is 'GGUF' (47 47 55 46)
                if data != Data([0x47, 0x47, 0x55, 0x46]) {
                    print("LlamaWrapper: ERROR - Invalid GGUF header!")
                    // Try to see if it's HTML
                    if let stringHead = String(data: data, encoding: .utf8) {
                        print("LlamaWrapper: Header starts with: \(stringHead)")
                    }
                    throw NSError(domain: "LlamaError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid model file. Expected GGUF format but found magic bytes: \(magicBytes). The file might be corrupted or an error page."])
                }
            }
            try? fileHandle.close()
        }
        
        // 2. Load model with Metal acceleration first
        var header = llama_model_default_params()
        header.n_gpu_layers = 12 
        
        print("LlamaWrapper: Attempting load with Metal (12 layers)...")
        self.model = path.withCString { cPath in
            return llama_load_model_from_file(cPath, header)
        }
        
        // 3. Fallback to CPU if Metal fails
        if self.model == nil {
            print("LlamaWrapper: Metal load failed. Retrying with CPU only...")
            header.n_gpu_layers = 0
            self.model = path.withCString { cPath in
                return llama_load_model_from_file(cPath, header)
            }
        }
        
        if self.model == nil {
            print("LlamaWrapper: Load failed on both Metal and CPU.")
            throw NSError(domain: "LlamaError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load model even on CPU. This usually means the architecture is unsupported by this version of llama.cpp or the file is corrupted."])
        }
        
        let gpuUsed = header.n_gpu_layers > 0
        print("LlamaWrapper: Model loaded successfully (\(gpuUsed ? "Metal" : "CPU")).")
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
        
        print("LlamaWrapper: Creating context...")
        var params = llama_context_default_params()
        params.n_ctx = 2048
        
        // Pass the opaque pointer
        self.context = llama_new_context_with_model(model.model, params)
        
        if self.context == nil {
            throw NSError(domain: "LlamaError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
        
        print("LlamaWrapper: Context created. Init batch...")
        print("LlamaWrapper: Context created. Init batch...")
        // Initialize batch with same size as context for safety
        self.batch = llama_batch_init(2048, 0, 1) 
    }
    
    deinit {
        llama_batch_free(batch)
        if let context = context {
            llama_free(context)
        }
    }
    
    func completion(_ prompt: String, onToken: (String) -> Void) async {
        guard let ctx = context, let mdl = model.model else { return }
        
        // 1. Tokenize prompt
        var tokens = tokenize(text: prompt, addBos: true)
        if tokens.isEmpty {
             print("LlamaWrapper: Tokenization yielded empty result.")
             return
        }
        
        // Cap tokens to batch size - 1 to leave room for one generated token
        if tokens.count > 2047 {
            tokens = Array(tokens.suffix(2047))
        }
        
        // 2. Evaluate prompt
        batch.n_tokens = Int32(tokens.count)
        
        for i in 0..<tokens.count {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        // Enable logits for the last token to sample next
        batch.logits[tokens.count - 1] = 1 
        
        if llama_decode(ctx, batch) != 0 {
            print("LlamaWrapper: llama_decode failed")
            onToken("Error: Inference failed (llama_decode error).")
            return
        }
        
        var n_cur = batch.n_tokens
        
        // 3. Generation loop
        // Increased limit for more natural answers
        for _ in 0..<500 {
            let n_vocab = llama_n_vocab(mdl)
            let logits = llama_get_logits_ith(ctx, batch.n_tokens - 1)
            
            var max_logit = -Float.infinity
            var best_token_id: llama_token = 0
            
            if let logits = logits {
                for id in 0..<n_vocab {
                   let logit = logits[Int(id)]
                   if logit > max_logit {
                       max_logit = logit
                       best_token_id = id
                   }
                }
            }
            
            if best_token_id == llama_token_eos(mdl) {
                print("LlamaWrapper: Reached EOS.")
                break
            }
            
            let piece = token_to_piece(token: best_token_id)
            onToken(piece)
            
            // Check context limits
            if n_cur >= 2048 {
                print("LlamaWrapper: Context full.")
                break
            }
            
            // Prepare next batch (single token)
            batch.n_tokens = 1
            batch.token[0] = best_token_id
            batch.pos[0] = n_cur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1 
            
            n_cur += 1
            
            if llama_decode(ctx, batch) != 0 {
                print("LlamaWrapper: llama_decode failed in loop.")
                break
            }
            
            await Task.yield() 
        }
    }
    
    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        guard let mdl = model.model else { return [] }
        
        // Initial estimate: 1 token per byte + BOS
        let n_tokens = text.utf8.count + (addBos ? 1 : 0)
        var tokens = [llama_token](repeating: 0, count: n_tokens)
        
        let n = llama_tokenize(mdl, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), addBos, false)
        
        if n < 0 {
             // Buffer too small, use the value of -n to resize
             let size = Int(-n)
             tokens = [llama_token](repeating: 0, count: size)
             let n2 = llama_tokenize(mdl, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), addBos, false)
             if n2 < 0 { return [] }
             return Array(tokens.prefix(Int(n2)))
        }
        
        return Array(tokens.prefix(Int(n)))
    }
    
    private func token_to_piece(token: llama_token) -> String {
        guard let mdl = model.model else { return "" }
        
        var buf = [CChar](repeating: 0, count: 64) 
        var n = llama_token_to_piece(mdl, token, &buf, Int32(buf.count), false)
        
        if n < 0 {
            let size = Int(-n)
            buf = [CChar](repeating: 0, count: size)
            n = llama_token_to_piece(mdl, token, &buf, Int32(buf.count), false)
        }
        
        if n > 0 {
            // Use accurate byte length for string conversion
            let data = Data(bytes: buf, count: Int(n))
            return String(data: data, encoding: .utf8) ?? ""
        }
        
        return ""
    }
}
