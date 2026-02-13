import SwiftUI
import UIKit

struct ContentView: View {
    @State private var isChatVisible = false
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
                isOpaque: true,
                onSelectFile: { _ in },
                showingSettings: $showingSettings,
                showingNewChatDialog: $showingNewChatDialog
            )
            .opacity(isChatVisible ? 0 : 1.0)
            .animation(.easeInOut, value: isChatVisible)
            .ignoresSafeArea()

            GeometryReader { geometry in
                let collapsedHeight: CGFloat = 110

                VStack(spacing: 0) {
                    ChatView(
                        chatManager: chatManager,
                        llmEngine: llmEngine,
                        agentManager: agentManager,
                        modelDownloader: modelDownloader,
                        onShowSettings: { showingSettings = true }
                    )
                    .frame(height: geometry.size.height)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: isChatVisible ? 0 : 30, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
                }
                .frame(height: isChatVisible ? geometry.size.height : collapsedHeight, alignment: .top)
                .offset(y: isChatVisible ? 0 : geometry.size.height - collapsedHeight)
                .offset(y: dragOffset)
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.height
                            if isChatVisible {
                                if translation > 0 {
                                    dragOffset = translation
                                    dismissKeyboard()
                                }
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
                                if value.translation.height > threshold {
                                    dismissKeyboard()
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
