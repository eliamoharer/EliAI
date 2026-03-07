import SwiftUI

@main
struct EliAIApp: App {
    @State private var fileSystem = FileSystemManager()
    @State private var llmEngine = LLMEngine()
    @State private var modelDownloader = ModelDownloader()
    @State private var chatManager: ChatManager
    @State private var agentManager: AgentManager
    @State private var taskManager: TaskManager

    init() {
        let fs = FileSystemManager()
        let tm = TaskManager(fileSystem: fs)
        _fileSystem = State(initialValue: fs)
        _chatManager = State(initialValue: ChatManager(fileSystem: fs))
        _taskManager = State(initialValue: tm)
        _agentManager = State(initialValue: AgentManager(fileSystem: fs, taskManager: tm))
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
            .onAppear {
                taskManager.requestNotificationPermission()
            }
        }
    }
}
