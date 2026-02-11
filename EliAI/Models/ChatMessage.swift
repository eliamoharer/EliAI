import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var isStreaming: Bool

    enum Role: String, Codable, Equatable {
        case user
        case assistant
        case system
        case tool
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.isStreaming = isStreaming
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tool Call

struct ToolCall: Identifiable, Codable {
    let id: UUID
    let toolName: String
    var parameters: [String: String]
    var result: String?
    var status: ToolStatus

    enum ToolStatus: String, Codable {
        case pending
        case executing
        case success
        case failed
    }

    init(
        id: UUID = UUID(),
        toolName: String,
        parameters: [String: String],
        result: String? = nil,
        status: ToolStatus = .pending
    ) {
        self.id = id
        self.toolName = toolName
        self.parameters = parameters
        self.result = result
        self.status = status
    }
}

// MARK: - Convenience

extension ChatMessage {
    static func userMessage(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistantMessage(_ content: String, streaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, isStreaming: streaming)
    }

    static func systemMessage(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    static func toolMessage(_ content: String, toolCalls: [ToolCall]) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCalls: toolCalls)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
