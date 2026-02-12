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
                        modelDownloader: modelDownloader // Pass modelDownloader
                    )
                    .frame(height: geometry.size.height)
                    .background(Color.white) // This will be overridden by ChatView's internal background
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
                }
                .offset(y: isChatVisible ? 0 : geometry.size.height - 120) // 120px peek
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if isChatVisible {
                                // Dragging down (positive) allowed
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                } else {
                                    // Elastic resistance dragging up
                                    dragOffset = value.translation.height / 3
                                }
                            } else {
                                // Dragging up (negative) allowed
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
                                        isChatVisible = true // Snap back
                                    }
                                }
                            } else {
                                if value.translation.height < -threshold {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isChatVisible = true
                                        isExplorerOpaque = false // Ensure explicit focus on chat
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isChatVisible = false // Snap back
                                    }
                                }
                            }
                            withAnimation {
                                dragOffset = 0
                            }
                        }
                )
            }
            
            // Control Handle logic moved inside ChatView for cleaner UI or kept here overlay?
            // Let's keep a visual cue if hidden
            if !isChatVisible {
                VStack {
                    Spacer()
                    Capsule()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.bottom, 50)
                        .allowsHitTesting(false)
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
