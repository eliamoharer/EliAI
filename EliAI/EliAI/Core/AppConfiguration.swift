import Foundation

struct AppConfiguration {
    struct RemoteModelConfig: Identifiable {
        let id: String
        let displayName: String
        let fileName: String
        let urlString: String
        let profile: ModelProfile
    }

    static let remoteModels: [RemoteModelConfig] = [
        RemoteModelConfig(
            id: "qwen3-1.7b-q4km",
            displayName: "Qwen 3 1.7B (Q4_K_M)",
            fileName: "Qwen3-1.7B-Q4_K_M.gguf",
            urlString: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
            profile: .qwen3
        ),
        RemoteModelConfig(
            id: "lfm2.5-1.2b-thinking-q4km",
            displayName: "LFM 2.5 1.2B Thinking (Q4_K_M)",
            fileName: "LFM2.5-1.2B-Thinking-Q4_K_M.gguf",
            urlString: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF/resolve/main/LFM2.5-1.2B-Thinking-Q4_K_M.gguf",
            profile: .lfm25
        ),
        RemoteModelConfig(
            id: "lfm2.5-1.2b-instruct-q4km",
            displayName: "LFM 2.5 1.2B Instruct (Q4_K_M)",
            fileName: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            urlString: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            profile: .lfm25
        )
    ]
    
    static let defaultModelID = "qwen3-1.7b-q4km"
    
    struct Keys {
        static let responseStyle = "responseStyle"
        static let selectedRemoteModelID = "selectedRemoteModelID"
        static let activeModelName = "activeModelName"
    }
}
