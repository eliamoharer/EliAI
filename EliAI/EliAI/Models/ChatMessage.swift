import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    
    enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }
    
    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date(), toolCalls: [ToolCall]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
    }
}
