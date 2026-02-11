import Foundation

// MARK: - Chat Manager
// Persists chat sessions as JSON files in the chats/ directory

@Observable
class ChatManager {
    let fileSystem: FileSystemManager
    var sessions: [ChatSession] = []
    var currentSession: ChatSession?

    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
        loadSessions()
    }

    // MARK: - Session Management

    func createSession(name: String = "New Chat") -> ChatSession {
        var session = ChatSession(name: name)
        // Insert system prompt
        session.messages.append(
            ChatMessage.systemMessage(AgentSystemPrompt.prompt)
        )
        sessions.insert(session, at: 0)
        currentSession = session
        saveSession(session)
        return session
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        let fileName = "chats/\(session.id.uuidString).json"
        try? fileSystem.deleteFile(relativePath: fileName)

        if currentSession?.id == session.id {
            currentSession = sessions.first
        }
    }

    func renameSession(_ session: ChatSession, to name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].name = name
        if currentSession?.id == session.id {
            currentSession?.name = name
        }
        saveSession(sessions[idx])
    }

    func switchToSession(_ session: ChatSession) {
        currentSession = session
    }

    // MARK: - Message Management

    func addMessage(_ message: ChatMessage) {
        guard var session = currentSession else { return }
        session.addMessage(message)
        currentSession = session

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
        saveSession(session)
    }

    func updateLastAssistantMessage(with content: String) {
        guard var session = currentSession else { return }
        session.updateLastAssistantMessage(with: content)
        currentSession = session

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
    }

    func saveCurrentSession() {
        guard let session = currentSession else { return }
        saveSession(session)
    }

    // MARK: - Persistence

    private func saveSession(_ session: ChatSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(session),
              let json = String(data: data, encoding: .utf8) else { return }

        let fileName = "chats/\(session.id.uuidString).json"
        try? fileSystem.createFile(relativePath: fileName, content: json)
    }

    func loadSessions() {
        let chatsDir = fileSystem.documentsURL.appendingPathComponent("chats")
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(at: chatsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [ChatSession] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let session = try? decoder.decode(ChatSession.self, from: data) {
                loaded.append(session)
            }
        }

        // Sort by most recent
        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }

        // Set current to most recent or create new
        currentSession = sessions.first
    }
}
