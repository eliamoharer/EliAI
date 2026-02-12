import Foundation

struct SamplingPreset: Equatable {
    let temperature: Double
    let topP: Double
    let repeatPenalty: Double
}

enum ModelProfile: String, CaseIterable, Codable {
    case qwen3
    case lfm25
    case generic

    var displayName: String {
        switch self {
        case .qwen3: return "Qwen 3"
        case .lfm25: return "LFM 2.5"
        case .generic: return "Generic GGUF"
        }
    }

    var sampling: SamplingPreset {
        switch self {
        case .qwen3:
            return SamplingPreset(temperature: 0.7, topP: 0.8, repeatPenalty: 1.1)
        case .lfm25:
            return SamplingPreset(temperature: 0.1, topP: 0.1, repeatPenalty: 1.05)
        case .generic:
            return SamplingPreset(temperature: 0.6, topP: 0.85, repeatPenalty: 1.1)
        }
    }

    func formatPrompt(messages: [ChatMessage], systemPrompt: String) -> String {
        let resolvedSystemPrompt = systemPrompt.isEmpty
            ? "You are EliAI, an intelligent and helpful assistant that can manage files, tasks, and memories."
            : systemPrompt

        switch self {
        case .qwen3, .lfm25:
            return formatChatML(messages: messages, systemPrompt: resolvedSystemPrompt)
        case .generic:
            return formatGeneric(messages: messages, systemPrompt: resolvedSystemPrompt)
        }
    }

    private func formatChatML(messages: [ChatMessage], systemPrompt: String) -> String {
        var prompt = ""
        prompt += "<|im_start|>system\n"
        prompt += systemPrompt
        prompt += "\n<|im_end|>\n"

        for message in messages {
            prompt += "<|im_start|>\(message.role.rawValue)\n"
            prompt += message.content
            prompt += "\n<|im_end|>\n"
        }

        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    private func formatGeneric(messages: [ChatMessage], systemPrompt: String) -> String {
        var prompt = "System: \(systemPrompt)\n\n"
        for message in messages {
            switch message.role {
            case .user:
                prompt += "User: \(message.content)\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n"
            case .system:
                prompt += "System: \(message.content)\n"
            case .tool:
                prompt += "Tool: \(message.content)\n"
            }
        }
        prompt += "Assistant: "
        return prompt
    }

    static func fromHints(fileName: String, metadataHints: Set<String>) -> ModelProfile {
        let lower = fileName.lowercased()

        if lower.contains("qwen3") || lower.contains("qwen-3") || metadataHints.contains("qwen") {
            return .qwen3
        }

        if lower.contains("lfm") || lower.contains("liquid") || metadataHints.contains("lfm") {
            return .lfm25
        }

        return .generic
    }
}
