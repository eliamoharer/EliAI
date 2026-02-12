import Foundation
import llama

// Fundamental Fix: Modernized LlamaWrapper for Official llama.cpp (b4600+)
// Optimized for iPhone 15 (A16) with LiquidAI LFM 2.5 support.

class LlamaModel {
    var model: OpaquePointer?
    
    // Ensure backend is initialized exactly once
    private static let initializeBackend: Void = {
        print("LlamaWrapper: Initializing official llama.cpp backend...")
        llama_backend_init()
        
        // Register a log callback to capture C++ errors
        llama_log_set({ level, text, user_data in
            if let text = text {
                let message = String(cString: text)
                print("LlamaLog [\(level)]: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }, nil)
    }()
    
    init(path: String) throws {
        _ = LlamaModel.initializeBackend
        
        print("LlamaWrapper: Loading model architecture for LFM compatibility...")
        
        // 1. Diagnostics
        let attr = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attr[FileAttributeKey.size] as? UInt64 ?? 0
        print("LlamaWrapper: Physical file size: \(fileSize / 1024 / 1024) MB")
        
        if let fileHandle = FileHandle(forReadingAtPath: path) {
            if let data = try? fileHandle.read(upToCount: 4) {
                if data != Data([0x47, 0x47, 0x55, 0x46]) {
                    throw NSError(domain: "LlamaError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid GGUF header. Download likely corrupted or manual error."])
                }
            }
            try? fileHandle.close()
        }

        // 2. Load Model
        var m_params = llama_model_default_params()
        m_params.n_gpu_layers = 16 // GPU offload for A16
        m_params.use_mmap = false  // ESSENTIAL: Forced RAM load for iOS Sandbox stability
        m_params.use_mlock = true  // Pin memory
        
        print("LlamaWrapper: System Info - \(String(cString: llama_print_system_info()))")
        
        self.model = path.withCString { cPath in
            return llama_model_load_from_file(cPath, m_params)
        }
        
        if self.model == nil {
            print("LlamaWrapper: Metal load failed. Retrying with CPU-only...")
            m_params.n_gpu_layers = 0
            self.model = path.withCString { cPath in
                return llama_model_load_from_file(cPath, m_params)
            }
        }
        
        if self.model == nil {
            throw NSError(domain: "LlamaError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Library could not parse LFM architecture. Ensure official llama.cpp master is linked."])
        }
        
        // Architecture verification
        var arch = [CChar](repeating: 0, count: 64)
        llama_model_meta_val_str(self.model, "general.architecture", &arch, arch.count)
        let archName = String(cString: arch)
        print("LlamaWrapper: SUCCESS! Architecture detected: \(archName)")
        
        let n_vocab = llama_model_n_vocab(self.model)
        print("LlamaWrapper: Model Vocab size: \(n_vocab)")
    }
    
    deinit {
        if let model = model {
            llama_model_free(model)
        }
    }
}

class LlamaContext {
    var context: OpaquePointer?
    var model: LlamaModel
    var batch: llama_batch
    
    init(model: LlamaModel) throws {
        self.model = model
        
        var c_params = llama_context_default_params()
        c_params.n_ctx = 2048
        c_params.n_batch = 2048
        c_params.n_threads = 4       // Optimized for A16 (2P + 2E or 4E mix)
        c_params.n_threads_batch = 4
        
        self.context = llama_init_from_model(model.model, c_params)
        
        if self.context == nil {
            throw NSError(domain: "LlamaError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Context initialization failed."])
        }
        
        // Initialize batch (pre-allocated C arrays)
        self.batch = llama_batch_init(2048, 0, 1)
        print("LlamaWrapper: Batch initialized with 2048 tokens capacity.")
    }
    
    deinit {
        llama_batch_free(batch)
        if let context = context {
            llama_free(context)
        }
    }
    
    func completion(_ prompt: String, onToken: (String) -> Void) async {
        guard let ctx = context, let mdl = model.model else { return }
        
        var tokens = tokenize(text: prompt, addBos: true)
        if tokens.isEmpty { return }
        
        // Context sliding window (simplified: take last 2047)
        if tokens.count > 2047 { tokens = Array(tokens.suffix(2047)) }
        
        // 1. Process Initial Prompt
        batch.n_tokens = Int32(tokens.count)
        for i in 0..<tokens.count {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.logits[tokens.count - 1] = 1 // Only want logits for the last token
        
        if llama_decode(ctx, batch) != 0 {
            print("LlamaWrapper: Initial prompt decode failed.")
            return
        }
        
        var n_cur = Int32(tokens.count)
        
        // 2. Generation Loop
        for _ in 0..<500 {
            let n_vocab = llama_model_n_vocab(mdl)
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
            
            if best_token_id == llama_model_token_eos(mdl) { 
                print("LlamaWrapper: EOS encountered.")
                break 
            }
            
            let piece = token_to_piece(token: best_token_id)
            onToken(piece)
            
            // Check limits
            if n_cur >= 2048 { break }
            
            // Prepare single-token batch for next step
            batch.n_tokens = 1
            batch.token[0] = best_token_id
            batch.pos[0] = n_cur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            
            n_cur += 1
            if llama_decode(ctx, batch) != 0 {
                print("LlamaWrapper: Decode failed in generation loop.")
                break 
            }
            
            await Task.yield()
        }
    }
    
    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        guard let mdl = model.model else { return [] }
        var tokens = [llama_token](repeating: 0, count: text.utf8.count + 8)
        let n = llama_tokenize(mdl, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), addBos, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            let n2 = llama_tokenize(mdl, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), addBos, true)
            return Array(tokens.prefix(Int(n2)))
        }
        return Array(tokens.prefix(Int(n)))
    }
    
    private func token_to_piece(token: llama_token) -> String {
        guard let mdl = model.model else { return "" }
        var buf = [CChar](repeating: 0, count: 128)
        // llama_token_to_piece signature: (model, token, buf, length, lstrip, special)
        let n = llama_token_to_piece(mdl, token, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            buf = [CChar](repeating: 0, count: Int(-n))
            let n2 = llama_token_to_piece(mdl, token, &buf, Int32(buf.count), 0, false)
            let data = Data(bytes: buf, count: Int(n2))
            return String(data: data, encoding: .utf8) ?? ""
        }
        let data = Data(bytes: buf, count: Int(n))
        return String(data: data, encoding: .utf8) ?? ""
    }
}
