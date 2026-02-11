import Foundation

// MARK: - Chat Session

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var name: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        name: String = "New Chat",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    var lastMessage: ChatMessage? {
        messages.last(where: { $0.role != .system })
    }

    var messageCount: Int {
        messages.filter { $0.role != .system }.count
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var preview: String {
        if let last = lastMessage {
            return String(last.content.prefix(80))
        }
        return "Empty chat"
    }

    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()
    }

    mutating func updateLastAssistantMessage(with content: String) {
        if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages[idx].content = content
            updatedAt = Date()
        }
    }
}
