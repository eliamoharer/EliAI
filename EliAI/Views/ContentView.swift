import SwiftUI

// MARK: - Content View
// Root view managing the layered UI: translucent file explorer background + chat foreground

struct ContentView: View {
    @State private var llmEngine = LLMEngine()
    @State private var fileSystem = FileSystemManager()
    @State private var agentManager: AgentManager
    @State private var chatManager: ChatManager
    @State private var settings = AppSettings()
    @State private var downloader = ModelDownloader()

    // UI State
    @State private var chatOffset: CGFloat = UIScreen.main.bounds.height * 0.6
    @State private var isDragging = false
    @State private var backgroundInteracting = false
    @State private var showNewChatDialog = false
    @State private var showModelManager = false

    private let minChatOffset: CGFloat = 60  // Chat fully up (showing top bar)
    private let maxChatOffset: CGFloat = UIScreen.main.bounds.height * 0.75

    init() {
        let fs = FileSystemManager()
        _fileSystem = State(initialValue: fs)
        _agentManager = State(initialValue: AgentManager(fileSystem: fs))
        _chatManager = State(initialValue: ChatManager(fileSystem: fs))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background — white base
                Color.white
                    .ignoresSafeArea()

                // LAYER 1: File Explorer (background)
                fileExplorerLayer
                    .opacity(backgroundOpacity)
                    .allowsHitTesting(chatOffset > geo.size.height * 0.4)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            backgroundInteracting = true
                        }
                    }

                // LAYER 2: Chat (foreground, slides up)
                chatLayer(geo: geo)
            }
        }
        .sheet(isPresented: $showNewChatDialog) {
            NewChatDialog { name in
                let _ = chatManager.createSession(name: name)
                showNewChatDialog = false
            }
            .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showModelManager) {
            ModelManagerView(
                downloader: $downloader,
                fileSystem: fileSystem,
                llmEngine: llmEngine
            )
        }
        .onAppear {
            setupInitialState()
        }
    }

    // MARK: - File Explorer Layer

    private var fileExplorerLayer: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("EliAI")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.8))

                Spacer()

                // Model status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(llmEngine.isLoaded ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(llmEngine.isLoaded ? "Ready" : "No Model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onTapGesture {
                    showModelManager = true
                }

                Button {
                    showModelManager = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // File Explorer Content
            FileExplorerView(
                fileSystem: fileSystem,
                chatManager: chatManager,
                onNewChat: {
                    showNewChatDialog = true
                },
                onNewChatLongPress: {
                    showNewChatDialog = true
                },
                isInteracting: $backgroundInteracting
            )
        }
    }

    // MARK: - Chat Layer

    private func chatLayer(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            chatDragHandle

            // Chat content
            ChatView(
                llmEngine: llmEngine,
                agentManager: agentManager,
                chatManager: chatManager,
                settings: settings
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
        )
        .offset(y: chatOffset)
        .gesture(chatDragGesture(geo: geo))
    }

    // MARK: - Drag Handle

    private var chatDragHandle: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            if chatOffset > UIScreen.main.bounds.height * 0.3 {
                Text("Swipe up to chat")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Drag Gesture

    private func chatDragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                withAnimation(.interactiveSpring()) {
                    backgroundInteracting = false
                }
                let newOffset = chatOffset + value.translation.height
                chatOffset = max(minChatOffset, min(maxChatOffset, newOffset))
            }
            .onEnded { value in
                isDragging = false
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let midPoint = geo.size.height * 0.35

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if velocity < -100 || chatOffset < midPoint {
                        // Swipe up — show chat
                        chatOffset = minChatOffset
                    } else {
                        // Swipe down — show background
                        chatOffset = maxChatOffset
                    }
                }
            }
    }

    // MARK: - Computed Properties

    private var backgroundOpacity: Double {
        if backgroundInteracting {
            return 1.0
        }
        // Fade from 0.35 (when chat is down) to 0.0 (when chat is up)
        let range = maxChatOffset - minChatOffset
        let normalized = (chatOffset - minChatOffset) / range
        return Double(normalized) * 0.4 + 0.05
    }

    private var isChatExpanded: Bool {
        chatOffset < UIScreen.main.bounds.height * 0.3
    }

    // MARK: - Setup

    private func setupInitialState() {
        // Create initial chat if none exists
        if chatManager.currentSession == nil {
            let _ = chatManager.createSession(name: "New Chat")
        }

        // Try to load the default model
        Task {
            if let model = settings.selectedModel,
               fileSystem.modelExists(fileName: model.fileName) {
                let path = fileSystem.modelPath(fileName: model.fileName)
                do {
                    try await llmEngine.loadModel(at: path)
                } catch {
                    print("Failed to auto-load model: \(error)")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
