import SwiftUI

@main
struct EliAIApp: App {
    @State private var fileSystem: FileSystemManager
    @State private var llmEngine: LLMEngine
    @State private var modelDownloader = ModelDownloader()
    @State private var chatManager: ChatManager
    @State private var agentManager: AgentManager
    @State private var taskManager: TaskManager
    @State private var phoneModeManager: PhoneModeManager
    @State private var chatCoordinator: ChatCoordinator

    init() {
        let fs = FileSystemManager()
        let tm = TaskManager(fileSystem: fs)
        let pmm = PhoneModeManager(fileSystem: fs)
        let cm = ChatManager(fileSystem: fs)
        let llm = LLMEngine()
        let am = AgentManager(fileSystem: fs, taskManager: tm, phoneModeManager: pmm)
        
        _fileSystem = State(initialValue: fs)
        _chatManager = State(initialValue: cm)
        _taskManager = State(initialValue: tm)
        _phoneModeManager = State(initialValue: pmm)
        _agentManager = State(initialValue: am)
        _llmEngine = State(initialValue: llm)
        _chatCoordinator = State(initialValue: ChatCoordinator(chatManager: cm, llmEngine: llm, agentManager: am))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(fileSystem)
                .environment(llmEngine)
                .environment(modelDownloader)
                .environment(chatManager)
                .environment(agentManager)
                .environment(taskManager)
                .environment(phoneModeManager)
                .environment(chatCoordinator)
            .onAppear {
                taskManager.requestNotificationPermission()
                Task {
                    await phoneModeManager.requestAllPermissions()
                }
            }
        }
    }
}
