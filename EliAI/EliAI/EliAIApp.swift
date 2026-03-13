import SwiftUI

@main
struct EliAIApp: App {
    @State private var fileSystem = FileSystemManager()
    @State private var llmEngine = LLMEngine()
    @State private var modelDownloader = ModelDownloader()
    @State private var chatManager: ChatManager
    @State private var agentManager: AgentManager
    @State private var taskManager: TaskManager
    @State private var phoneModeManager: PhoneModeManager

    init() {
        let fs = FileSystemManager()
        let tm = TaskManager(fileSystem: fs)
        let pmm = PhoneModeManager(fileSystem: fs)
        _fileSystem = State(initialValue: fs)
        _chatManager = State(initialValue: ChatManager(fileSystem: fs))
        _taskManager = State(initialValue: tm)
        _phoneModeManager = State(initialValue: pmm)
        _agentManager = State(initialValue: AgentManager(fileSystem: fs, taskManager: tm, phoneModeManager: pmm))
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
