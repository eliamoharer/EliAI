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
                VStack(spacing: 0) {
                    ChatView(
                        chatManager: chatManager,
                        llmEngine: llmEngine,
                        agentManager: agentManager,
                        modelDownloader: modelDownloader
                    )
                    // Ensure full height
                    .frame(height: geometry.size.height)
                    .background(Color.white)
                    // Clip top corners only.
                    .clipShape(RoundedRectangle(cornerRadius: isChatVisible ? 0 : 30, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
                }
                // If chat is visible, offset is 0. If hidden/peaking, offset is height - peek.
                // However, user said "chat still doesnt touch the bottom".
                // If isChatVisible is true, offset is 0.
                .offset(y: isChatVisible ? 0 : geometry.size.height - 120) 
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                             // Simple drag logic
                             let translation = value.translation.height
                             if isChatVisible {
                                 // Dragging down from full screen
                                 if translation > 0 { dragOffset = translation }
                             } else {
                                 // Dragging up from peek
                                 if translation < 0 { dragOffset = translation }
                             }
                        }
                        .onEnded { value in
                            let threshold = geometry.size.height * 0.2
                            if isChatVisible {
                                if value.translation.height > threshold {
                                    withAnimation(.spring()) { isChatVisible = false }
                                } else {
                                    withAnimation(.spring()) { isChatVisible = true }
                                }
                            } else {
                                if value.translation.height < -threshold {
                                    withAnimation(.spring()) { isChatVisible = true }
                                } else {
                                    withAnimation(.spring()) { isChatVisible = false }
                                }
                            }
                            withAnimation { dragOffset = 0 }
                        }
                )
            }
            .padding(.bottom, 0) // Explicitly ensure no bottom padding
            .ignoresSafeArea(.keyboard) // critical for chat input
            
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
        .onChange(of: modelDownloader.localModelURL) { oldUrl, newUrl in
            if let url = newUrl {
                Task {
                    try? await llmEngine.loadModel(at: url)
                }
            }
        }
    }
}
