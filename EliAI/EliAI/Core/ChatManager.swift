import Foundation
import Observation

@Observable
class ChatManager {
    var sessions: [ChatSession] = []
    var currentSession: ChatSession?
    
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
        loadSessions()
        if currentSession == nil {
            currentSession = sessions.first
        }
    }
    
    func createNewSession(title: String = "New Chat") {
        let session = ChatSession(title: title)
        sessions.insert(session, at: 0)
        currentSession = session
        saveSession(session)
        AppLogger.info("Created new chat session: \(title)", category: .app)
    }
    
    func loadSessions() {
        // Load from file system 'chats/' directory
        // For simplicity, we'll assume JSON files
        do {
            let files = try fileSystem.listFiles(directory: "chats")
            var newSessions: [ChatSession] = []
            
            for file in files where file.hasSuffix(".json") {
                let content = try fileSystem.readFile(path: "chats/\(file)")
                if let data = content.data(using: .utf8),
                   let session = try? JSONDecoder().decode(ChatSession.self, from: data) {
                    newSessions.append(session)
                }
            }
            self.sessions = newSessions.sorted(by: { $0.updatedAt > $1.updatedAt })
            self.currentSession = self.sessions.first
        } catch {
            AppLogger.error("Error loading sessions: \(error.localizedDescription)", category: .app)
        }
    }
    
    func saveSession(_ session: ChatSession) {
        do {
            let data = try JSONEncoder().encode(session)
            if let jsonString = String(data: data, encoding: .utf8) {
                try fileSystem.createFile(path: "chats/\(session.id.uuidString).json", content: jsonString)
            }
        } catch {
            AppLogger.error("Error saving session: \(error.localizedDescription)", category: .app)
        }
    }
    
    func addMessage(_ message: ChatMessage) {
        guard var session = currentSession else { return }
        session.messages.append(message)
        session.updatedAt = Date()
        currentSession = session
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        
        saveSession(session)
        AppLogger.debug("Message appended role=\(message.role.rawValue)", category: .app)
    }

    func updateLastMessage(_ message: ChatMessage, persist: Bool = true) {
        guard var session = currentSession, !session.messages.isEmpty else { return }
        session.messages[session.messages.count - 1] = message
        session.updatedAt = Date()
        currentSession = session

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }

        if persist {
            saveSession(session)
        }
    }

    func removeMessage(id: UUID) {
        guard var session = currentSession else { return }
        let originalCount = session.messages.count
        session.messages.removeAll { $0.id == id }
        guard session.messages.count != originalCount else { return }

        session.updatedAt = Date()
        currentSession = session
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        saveSession(session)
    }

    func clearCurrentSession() {
        guard var session = currentSession else { return }
        session.messages.removeAll()
        session.updatedAt = Date()
        currentSession = session

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }

        saveSession(session)
        AppLogger.info("Cleared messages for session: \(session.title)", category: .app)
    }
}
