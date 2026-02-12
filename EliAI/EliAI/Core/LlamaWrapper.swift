import Foundation
import LlamaSwift

// Fundamental Fix: Modernized LlamaWrapper for Official llama.cpp (b4600+)
// Now features UI-accessible diagnostic logs.

class LlamaModel: @unchecked Sendable {
    var model: OpaquePointer?
    
    // UI Diagnostic: Capture internal C++ errors
    static var lastLogMessages: [String] = []
    
    // Ensure backend is initialized exactly once
    private static let initializeBackend: Void = {
        print("LlamaWrapper: Initializing official llama.cpp backend...")
        llama_backend_init()
        
        llama_log_set({ level, text, user_data in
            if let text = text {
                let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    print("LlamaLog [\(level)]: \(message)")
                    // Keep last 10 lines for UI error reporting
                    LlamaModel.lastLogMessages.append(message)
                    if LlamaModel.lastLogMessages.count > 10 {
                        LlamaModel.lastLogMessages.removeFirst()
                    }
                }
            }
        }, nil)
    }()
    
    init(path: String) throws {
        _ = LlamaModel.initializeBackend
        LlamaModel.lastLogMessages.removeAll() // Start fresh
        
        print("LlamaWrapper: Loading model architecture...")
        
        // 1. Pre-flight checks
        let attr = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attr[FileAttributeKey.size] as? UInt64 ?? 0
        print("LlamaWrapper: File size: \(fileSize / 1024 / 1024) MB")
        
        if let fileHandle = FileHandle(forReadingAtPath: path) {
            if let data = try? fileHandle.read(upToCount: 4) {
                if data != Data([0x47, 0x47, 0x55, 0x46]) {
                    throw NSError(domain: "LlamaError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid GGUF header. Download likely corrupted."])
                }
            }
            try? fileHandle.close()
        }

        // 2. Load Model
        var m_params = llama_model_default_params()
        m_params.n_gpu_layers = 16 
        m_params.use_mmap = false  
        m_params.use_mlock = true  
        
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
            let logs = LlamaModel.lastLogMessages.joined(separator: "\n")
            throw NSError(domain: "LlamaError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Library could not parse model. C++ Logs:\n\(logs)"])
        }
        
        // Architecture diagnostics
        var arch = [CChar](repeating: 0, count: 64)
        llama_model_meta_val_str(self.model, "general.architecture", &arch, arch.count)
        print("LlamaWrapper: SUCCESS! Architecture: \(String(cString: arch))")
    }
    
    deinit {
        if let model = model {
            llama_model_free(model)
        }
    }
}

class LlamaContext: @unchecked Sendable {
    var context: OpaquePointer?
    var model: LlamaModel
    var batch: llama_batch
    
    init(model: LlamaModel) throws {
        self.model = model
        
        var c_params = llama_context_default_params()
        c_params.n_ctx = 2048
        c_params.n_batch = 2048
        c_params.n_threads = 4
        c_params.n_threads_batch = 4
        
        self.context = llama_init_from_model(model.model, c_params)
        
        if self.context == nil {
            let logs = LlamaModel.lastLogMessages.joined(separator: "\n")
            throw NSError(domain: "LlamaError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context. C++ Logs:\n\(logs)"])
        }
        
        self.batch = llama_batch_init(2048, 0, 1)
    }
    
    func resetContext() {
        guard let ctx = context else { return }
        print("LlamaWrapper: Clearing KV Cache...")
        llama_kv_cache_clear(ctx)
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
        
        var n_cur = Int32(tokens.count)
        
        // 3. Initialize high-quality sampler
        let n_vocab = llama_model_n_vocab(mdl)
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(n_vocab, 64, 1.1, 0.0, 0.0))
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.8))
        llama_sampler_chain_add(smpl, llama_sampler_init_softmax()) // CRITICAL for non-greedy
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(UInt32(Date().timeIntervalSince1970)))
        
        defer {
            llama_sampler_free(smpl)
        }
        
        // 4. Generation Loop
        for _ in 0..<500 {
            if Task.isCancelled { break }
            
            let id = llama_sampler_sample(smpl, ctx, batch.n_tokens - 1)
            
            if id == llama_model_token_eos(mdl) { break }
            
            let piece = token_to_piece(token: id)
            onToken(piece)
            
            if n_cur >= 2048 { break }
            
            batch.n_tokens = 1
            batch.token[0] = id
            batch.pos[0] = n_cur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            
            n_cur += 1
            if llama_decode(ctx, batch) != 0 { break }
            
            llama_sampler_accept(smpl, id)
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
