import Foundation

struct SamplingPreset: Equatable {
    let temperature: Double
    let topK: Int
    let topP: Double
    let repeatPenalty: Double
}

enum SamplingControlPreset: String, CaseIterable, Codable, Identifiable {
    case modelDefault
    case focused
    case balanced
    case creative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modelDefault:
            return "Model Default"
        case .focused:
            return "Focused"
        case .balanced:
            return "Balanced"
        case .creative:
            return "Creative"
        }
    }

    var details: String {
        switch self {
        case .modelDefault:
            return "Uses each model's recommended sampling values."
        case .focused:
            return "Temperature 0.1, top-k 40."
        case .balanced:
            return "Temperature 0.4, top-k 60."
        case .creative:
            return "Temperature 0.8, top-k 100."
        }
    }

    func apply(to base: SamplingPreset) -> SamplingPreset {
        switch self {
        case .modelDefault:
            return base
        case .focused:
            return SamplingPreset(
                temperature: 0.1,
                topK: 40,
                topP: base.topP,
                repeatPenalty: base.repeatPenalty
            )
        case .balanced:
            return SamplingPreset(
                temperature: 0.4,
                topK: 60,
                topP: base.topP,
                repeatPenalty: base.repeatPenalty
            )
        case .creative:
            return SamplingPreset(
                temperature: 0.8,
                topK: 100,
                topP: base.topP,
                repeatPenalty: base.repeatPenalty
            )
        }
    }
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
            return SamplingPreset(temperature: 0.7, topK: 50, topP: 0.9, repeatPenalty: 1.08)
        case .lfm25:
            return SamplingPreset(temperature: 0.1, topK: 50, topP: 0.9, repeatPenalty: 1.05)
        case .generic:
            return SamplingPreset(temperature: 0.6, topK: 50, topP: 0.9, repeatPenalty: 1.1)
        }
    }

    func formatPrompt(messages: [ChatMessage], systemPrompt: String) -> String {
        let resolvedSystemPrompt = systemPrompt.isEmpty
            ? "You are EliAI, a helpful assistant that can reason, solve math, and use local tools for files, memory, and tasks."
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
        if !systemPrompt.isEmpty {
            prompt += "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        }

        for message in messages {
            let role = promptRole(for: message)
            let content = promptContent(for: message)
            prompt += "<|im_start|>\(role)\n\(content)<|im_end|>\n"
        }

        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    private func formatGeneric(messages: [ChatMessage], systemPrompt: String) -> String {
        var prompt = ""
        if !systemPrompt.isEmpty {
             prompt += "System: \(systemPrompt)\n\n"
        }
        
        for message in messages {
            let role = genericRoleLabel(for: message)
            let content = promptContent(for: message)
            prompt += "\(role): \(content)\n"
        }
        prompt += "Assistant: "
        return prompt
    }

    private func promptRole(for message: ChatMessage) -> String {
        switch message.role {
        case .assistant:
            return "assistant"
        case .system:
            return "system"
        case .user, .tool:
            return "user"
        }
    }

    private func genericRoleLabel(for message: ChatMessage) -> String {
        switch message.role {
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        case .user, .tool:
            return "User"
        }
    }

    private func promptContent(for message: ChatMessage) -> String {
        if message.role == .tool {
            return "Tool result:\n\(message.content)"
        }
        return message.content
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
