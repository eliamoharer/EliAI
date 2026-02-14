import SwiftUI

@main
struct EliAIApp: App {
    @State private var fileSystem = FileSystemManager()
    @State private var llmEngine = LLMEngine()
    @State private var modelDownloader = ModelDownloader()
    @State private var chatManager: ChatManager
    @State private var agentManager: AgentManager

    init() {
        let fs = FileSystemManager()
        _fileSystem = State(initialValue: fs)
        _chatManager = State(initialValue: ChatManager(fileSystem: fs))
        _agentManager = State(initialValue: AgentManager(fileSystem: fs))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                fileSystem: fileSystem,
                llmEngine: llmEngine,
                modelDownloader: modelDownloader,
                chatManager: chatManager,
                agentManager: agentManager
            )
        }
    }
}
