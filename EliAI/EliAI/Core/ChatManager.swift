import Foundation

@Observable
class ChatManager {
    var sessions: [ChatSession] = []
    var currentSession: ChatSession?
    
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
        loadSessions()
    }
    
    func createNewSession(title: String = "New Chat") {
        let session = ChatSession(title: title)
        sessions.insert(session, at: 0)
        currentSession = session
        saveSession(session)
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
        } catch {
            print("Error loading sessions: \(error)")
        }
    }
    
    func saveSession(_ session: ChatSession) {
        do {
            let data = try JSONEncoder().encode(session)
            if let jsonString = String(data: data, encoding: .utf8) {
                try fileSystem.createFile(path: "chats/\(session.id.uuidString).json", content: jsonString)
            }
        } catch {
            print("Error saving session: \(error)")
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
    }
}
