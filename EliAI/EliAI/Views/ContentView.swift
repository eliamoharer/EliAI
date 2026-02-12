import SwiftUI

struct ContentView: View {
    @State private var isChatVisible = false
    @State private var isExplorerOpaque = false
    @State private var dragOffset: CGFloat = 0
    
    // Core Services
    // In iOS 17 with @Observable, we just initialize them. 
    // If they were ObservableObjects, we'd use @StateObject.
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
                modelDownloader: modelDownloader, // Pass modelDownloader
                isOpaque: isExplorerOpaque,
                onSelectFile: { file in
                    // Handle file selection (e.g. open in detail view or chat context)
                    // For now, it just navigates within its own view hierarchy
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
                        agentManager: agentManager,
                        modelDownloader: modelDownloader
                    )
                    .frame(height: geometry.size.height)
                    .background(Color.white)
                    // Removed bottom corner radius to stick to bottom
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    // We might want to mask the bottom corners if we want it "stuck"
                    // Or just remove the clipShape entirely for a full sheet look?
                    // User said "stuck to the bottom". 
                    // Let's keep top corners rounded, bottom square.
                    .mask(
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                            Rectangle().frame(height: 30) // Extensions
                        }
                    ) 
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
                }
                .offset(y: isChatVisible ? 0 : geometry.size.height - 120) // 120px peek
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if isChatVisible {
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                } else {
                                    dragOffset = value.translation.height / 3
                                }
                            } else {
                                if value.translation.height < 0 {
                                    dragOffset = value.translation.height
                                } else {
                                    dragOffset = value.translation.height / 3
                                }
                            }
                        }
                        .onEnded { value in
                            let threshold = geometry.size.height * 0.15
                            if isChatVisible {
                                if value.translation.height > threshold {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isChatVisible = false
                                        isExplorerOpaque = false
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isChatVisible = true
                                    }
                                }
                            } else {
                                if value.translation.height < -threshold {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isChatVisible = true
                                        isExplorerOpaque = false
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isChatVisible = false
                                    }
                                }
                            }
                            withAnimation {
                                dragOffset = 0
                            }
                        }
                )
            }
            
            // Removed visual cue (Capsule) as requested
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
