import Foundation
import llama

// Define the classes expected by LLMEngine

class LlamaModel {
    var model: OpaquePointer?
    
    // Ensure backend is initialized exactly once
    private static let initializeBackend: Void = {
        print("LlamaWrapper: Initializing generic backend...")
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
        // Trigger static initialization
        _ = LlamaModel.initializeBackend
        llama_backend_init()
        llama_numa_init(LLAMA_NUMA_STRATEGY_DISTRIBUTE)
        
        print("LlamaWrapper: Checking file at \(path)")
        if !FileManager.default.fileExists(atPath: path) {
            throw NSError(domain: "LlamaError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model file not found at \(path)"])
        }
        
        // Log file size
        let attr = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attr[FileAttributeKey.size] as? UInt64 ?? 0
        print("LlamaWrapper: File size is \(fileSize / 1024 / 1024) MB")
        
        // 1. Diagnostic magic byte check
        if let fileHandle = FileHandle(forReadingAtPath: path) {
            if let data = try? fileHandle.read(upToCount: 4) {
                if data != Data([0x47, 0x47, 0x55, 0x46]) {
                    throw NSError(domain: "LlamaError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid model file header (Not GGUF)."])
                }
            }
            try? fileHandle.close()
        }
        
        var m_params = llama_model_default_params()
        m_params.n_gpu_layers = 16 // Increase for 1.2B model on A16
        m_params.use_mmap = false  // Forced RAM load for reliability
        m_params.use_mlock = true  // Keep in RAM
        
        print("LlamaWrapper: System Info - \(String(cString: llama_print_system_info()))")
        print("LlamaWrapper: Loading model architecture...")
        
        self.model = path.withCString { cPath in
            return llama_model_load_from_file(cPath, m_params)
        }
        
        if self.model == nil {
            print("LlamaWrapper: Initial load failed. Retrying CPU-only...")
            m_params.n_gpu_layers = 0
            self.model = path.withCString { cPath in
                return llama_model_load_from_file(cPath, m_params)
            }
        }
        
        if self.model == nil {
            throw NSError(domain: "LlamaError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load model architecture. Ensure library version >= b4500 for LFM support."])
        }
        
        // Log Architecture Name
        var arch = [CChar](repeating: 0, count: 128)
        llama_model_meta_val_str(self.model, "general.architecture", &arch, arch.count)
        print("LlamaWrapper: SUCCESS! Loaded architecture: \(String(cString: arch))")
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
        c_params.n_threads = 4 // Optimize for A16 Efficiency Cores
        c_params.n_threads_batch = 4
        
        self.context = llama_init_from_model(model.model, c_params)
        
        if self.context == nil {
            throw NSError(domain: "LlamaError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
        
        // Latest llama_batch_init(n_tokens, n_embd, n_seq_max)
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
        
        var tokens = tokenize(text: prompt, addBos: true)
        if tokens.isEmpty { return }
        
        if tokens.count > 2047 { tokens = Array(tokens.suffix(2047)) }
        
        batch.n_tokens = Int32(tokens.count)
        for i in 0..<tokens.count {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.logits[tokens.count - 1] = 1 
        
        if llama_decode(ctx, batch) != 0 { return }
        
        var n_cur = batch.n_tokens
        
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
            
            if best_token_id == llama_token_eos(mdl) { break }
            
            let piece = token_to_piece(token: best_token_id)
            onToken(piece)
            
            if n_cur >= 2048 { break }
            
            batch.n_tokens = 1
            batch.token[0] = best_token_id
            batch.pos[0] = n_cur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1 
            
            n_cur += 1
            if llama_decode(ctx, batch) != 0 { break }
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
        // llama_token_to_piece(model, token, buf, length, lstrip, special)
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
