import SwiftUI

struct ContentView: View {
    @State private var isChatVisible = false
    @State private var isExplorerOpaque = false
    @State private var dragOffset: CGFloat = 0
    @State private var didAttemptFallbackModel = false

    @State private var fileSystem = FileSystemManager()
    @State private var llmEngine = LLMEngine()
    @State private var modelDownloader = ModelDownloader()

    @State private var chatManager: ChatManager
    @State private var agentManager: AgentManager

    @State private var showingSettings = false
    @State private var showingNewChatDialog = false

    init() {
        let fs = FileSystemManager()
        _fileSystem = State(initialValue: fs)
        _chatManager = State(initialValue: ChatManager(fileSystem: fs))
        _agentManager = State(initialValue: AgentManager(fileSystem: fs))
    }

    var body: some View {
        ZStack {
            FileExplorerView(
                fileSystem: fileSystem,
                chatManager: chatManager,
                modelDownloader: modelDownloader,
                isOpaque: isExplorerOpaque,
                onSelectFile: { _ in },
                showingSettings: $showingSettings,
                showingNewChatDialog: $showingNewChatDialog
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

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ChatView(
                        chatManager: chatManager,
                        llmEngine: llmEngine,
                        agentManager: agentManager,
                        modelDownloader: modelDownloader
                    )
                    .frame(height: geometry.size.height)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: isChatVisible ? 0 : 30, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
                }
                .offset(y: isChatVisible ? 0 : geometry.size.height - 120)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.height
                            if isChatVisible {
                                if translation > 0 { dragOffset = translation }
                            } else if translation < 0 {
                                dragOffset = translation
                            }
                        }
                        .onEnded { value in
                            let threshold = geometry.size.height * 0.2
                            if isChatVisible {
                                withAnimation(.spring()) {
                                    isChatVisible = !(value.translation.height > threshold)
                                }
                            } else {
                                withAnimation(.spring()) {
                                    isChatVisible = value.translation.height < -threshold
                                }
                            }
                            withAnimation { dragOffset = 0 }
                        }
                )
            }
            .sheet(isPresented: $showingNewChatDialog) {
                NewChatDialog(isPresented: $showingNewChatDialog) { name in
                    chatManager.createNewSession(title: name)
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationView {
                    SettingsView(modelDownloader: modelDownloader)
                        .navigationBarItems(trailing: Button("Done") { showingSettings = false })
                }
            }
            .padding(.bottom, 0)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-disableAutoModelLoad") {
                AppLogger.info("Auto model load disabled by launch argument.", category: .ui)
                return
            }

            modelDownloader.checkLocalModel()
            if let url = modelDownloader.localModelURL {
                attemptModelLoad(url: url)
            }
        }
        .onChange(of: modelDownloader.localModelURL) { _, newURL in
            guard let url = newURL else { return }
            attemptModelLoad(url: url)
        }
        .alert(
            "Model Loading Error",
            isPresented: Binding(
                get: { llmEngine.loadError != nil },
                set: { _ in llmEngine.loadError = nil }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = llmEngine.loadError {
                Text(error)
            }
        }
    }

    private func attemptModelLoad(url: URL) {
        do {
            try llmEngine.loadModel(at: url)
            didAttemptFallbackModel = false
        } catch {
            if !didAttemptFallbackModel,
               let fallbackURL = modelDownloader.fallbackModelURL(excluding: url.lastPathComponent),
               fallbackURL.lastPathComponent != url.lastPathComponent {
                didAttemptFallbackModel = true
                AppLogger.warning(
                    "Switching to fallback model \(fallbackURL.lastPathComponent) after load failure.",
                    category: .model
                )
                modelDownloader.activeModelName = fallbackURL.lastPathComponent
            }
        }
    }
}
