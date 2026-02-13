import SwiftUI
import UIKit

struct ContentView: View {
    @State private var isChatVisible = true
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
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.20),
                    Color.cyan.opacity(0.16),
                    Color.white.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            FileExplorerView(
                fileSystem: fileSystem,
                chatManager: chatManager,
                modelDownloader: modelDownloader,
                isOpaque: false,
                onSelectFile: { _ in },
                showingSettings: $showingSettings,
                showingNewChatDialog: $showingNewChatDialog
            )
            .opacity(1.0)
            .allowsHitTesting(!isChatVisible)
            .ignoresSafeArea()

            GeometryReader { geometry in
                let fullHeight = geometry.size.height + geometry.safeAreaInsets.bottom
                let expandedTopOffset: CGFloat = 0
                let peekVisibleHeight: CGFloat = 120
                let collapsedOffsetBase = max(0, fullHeight - peekVisibleHeight)
                let panelOffset = isChatVisible
                    ? expandedTopOffset + max(0, dragOffset)
                    : max(0, collapsedOffsetBase + min(0, dragOffset))

                ZStack(alignment: .bottom) {
                    ChatView(
                        chatManager: chatManager,
                        llmEngine: llmEngine,
                        agentManager: agentManager,
                        modelDownloader: modelDownloader,
                        onShowSettings: { showingSettings = true },
                        isCollapsed: !isChatVisible
                    )
                    .frame(height: fullHeight)
                    .clipShape(RoundedRectangle(cornerRadius: isChatVisible ? 0 : 28, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: -5)
                    .offset(y: panelOffset)
                    .zIndex(2)
                    .allowsHitTesting(true)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                if isChatVisible {
                                    if value.translation.height > 0 {
                                        dragOffset = value.translation.height
                                        dismissKeyboard()
                                    }
                                } else if value.translation.height < 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if isChatVisible {
                                    let collapseThreshold = geometry.size.height * 0.17
                                    if value.translation.height > collapseThreshold {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                            isChatVisible = false
                                        }
                                    }
                                } else {
                                    let expandThreshold: CGFloat = 70
                                    if value.translation.height < -expandThreshold {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                            isChatVisible = true
                                        }
                                    }
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                    )
                    .onTapGesture {
                        if !isChatVisible {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                isChatVisible = true
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
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
            UserDefaults.standard.register(defaults: ["responseStyle": "auto"])
            if chatManager.currentSession == nil {
                chatManager.createNewSession()
            }

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
        if llmEngine.isLoadingModel {
            return
        }
        if llmEngine.isLoaded, llmEngine.modelPath == url.path {
            return
        }

        Task { @MainActor in
            do {
                try await llmEngine.loadModel(at: url)
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
