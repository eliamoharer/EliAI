import SwiftUI

struct ContentView: View {
    @State private var isChatVisible = false
    @State private var isExplorerOpaque = false
    @State private var dragOffset: CGFloat = 0
    
    // Core Services
    @State private var fileSystem = FileSystemManager()
    @State private var llmEngine = LLMEngine()
    @State private var modelDownloader = ModelDownloader()
    
    // Derived Services
    @State private var chatManager: ChatManager
    @State private var agentManager: AgentManager
    @State private var taskManager: TaskManager
    @State private var memoryManager: MemoryManager
    
    init() {
        let fs = FileSystemManager()
        _fileSystem = State(initialValue: fs)
        _chatManager = State(initialValue: ChatManager(fileSystem: fs))
        _agentManager = State(initialValue: AgentManager(fileSystem: fs))
        _taskManager = State(initialValue: TaskManager(fileSystem: fs))
        _memoryManager = State(initialValue: MemoryManager(fileSystem: fs))
    }
    
    var body: some View {
        ZStack {
            // Background: File Explorer
            FileExplorerView(
                fileSystem: fileSystem,
                chatManager: chatManager,
                isOpaque: isExplorerOpaque,
                onSelectFile: { file in
                    // Handle file selection
                }
            )
            .opacity(isChatVisible ? 0 : (isExplorerOpaque ? 1.0 : 0.3))
            .animation(.easeInOut, value: isChatVisible)
            .animation(.easeInOut, value: isExplorerOpaque)
            .onTapGesture {
                withAnimation {
                    isExplorerOpaque = true
                }
            }
            .ignoresSafeArea()
            
            // Foreground: Chat Layer
            GeometryReader { geometry in
                VStack {
                    ChatView(
                        chatManager: chatManager,
                        llmEngine: llmEngine,
                        agentManager: agentManager
                    )
                    .frame(height: geometry.size.height)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                }
                .offset(y: isChatVisible ? 0 : geometry.size.height - 100) // 100px peek or hidden
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            let threshold = geometry.size.height * 0.2
                            if isChatVisible {
                                if value.translation.height > threshold {
                                    withAnimation {
                                        isChatVisible = false
                                        isExplorerOpaque = false // Reset explorer when revealing
                                    }
                                }
                            } else {
                                if value.translation.height < -threshold {
                                    withAnimation {
                                        isChatVisible = true
                                    }
                                }
                            }
                            withAnimation {
                                dragOffset = 0
                            }
                        }
                )
            }
            // Control Handle / Visual Cue
            VStack {
                Spacer()
                if !isChatVisible {
                    Capsule()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 40, height: 6)
                        .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            modelDownloader.checkLocalModel()
            if let url = modelDownloader.localModelURL {
                Task {
                    try? await llmEngine.loadModel(at: url)
                }
            }
        }
    }
}
