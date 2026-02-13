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
                let hiddenOffset = geometry.size.height + geometry.safeAreaInsets.bottom
                let panelOffset = isChatVisible
                    ? max(0, dragOffset)
                    : hiddenOffset + min(0, dragOffset)

                ZStack(alignment: .bottom) {
                    ChatView(
                        chatManager: chatManager,
                        llmEngine: llmEngine,
                        agentManager: agentManager,
                        modelDownloader: modelDownloader,
                        onShowSettings: { showingSettings = true }
                    )
                    .frame(height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: isChatVisible ? 0 : 28, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: -5)
                    .offset(y: panelOffset)
                    .zIndex(2)
                    .allowsHitTesting(isChatVisible)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard isChatVisible else { return }
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                    dismissKeyboard()
                                }
                            }
                            .onEnded { value in
                                guard isChatVisible else { return }
                                let threshold = geometry.size.height * 0.17
                                if value.translation.height > threshold {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                        isChatVisible = false
                                    }
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                    )

                    if !isChatVisible {
                        collapsedHandle
                            .padding(.bottom, max(8, geometry.safeAreaInsets.bottom))
                            .offset(y: min(0, dragOffset))
                            .zIndex(3)
                            .gesture(
                                DragGesture(minimumDistance: 6)
                                    .onChanged { value in
                                        if value.translation.height < 0 {
                                            dragOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        let threshold: CGFloat = 70
                                        if value.translation.height < -threshold {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                                isChatVisible = true
                                            }
                                        }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                            dragOffset = 0
                                        }
                                    }
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                    isChatVisible = true
                                }
                            }
                    }
                }
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

    private var collapsedHandle: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.primary.opacity(0.30))
                .frame(width: 48, height: 6)
            Text("Open Chat")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
    }
}
