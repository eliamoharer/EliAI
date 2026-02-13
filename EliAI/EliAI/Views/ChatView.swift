import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    var chatManager: ChatManager
    var llmEngine: LLMEngine
    var agentManager: AgentManager
    var modelDownloader: ModelDownloader
    var onShowSettings: () -> Void = {}
    var isCollapsed: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showFileImporter = false
    @State private var keyboardHeight: CGFloat = 0
    private let bottomAnchorID = "chatBottomAnchor"

    private var currentMessages: [ChatMessage] {
        chatManager.currentSession?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            topGrabber
            headerSection
            messagesSection
            inputSection
        }
        .background(chatPanelBackground)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    modelDownloader.importLocalModel(from: url)
                }
            case .failure(let error):
                modelDownloader.error = "Import failed: \(error.localizedDescription)"
                modelDownloader.log = "Import failed."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            let overlap = keyboardOverlap(from: notification)
            withAnimation(keyboardAnimation(for: notification)) {
                keyboardHeight = overlap
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            withAnimation(keyboardAnimation(for: notification)) {
                keyboardHeight = 0
            }
        }
    }

    private var topGrabber: some View {
        Capsule()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 42, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .opacity(isCollapsed ? 0 : 1)
            .frame(height: isCollapsed ? 0 : nil)
    }

    private var headerSection: some View {
        HStack {
            Text(chatManager.currentSession?.title ?? "EliAI")
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            headerTrailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isCollapsed ? 10 : 16)
    }

    @ViewBuilder
    private var headerTrailing: some View {
        if modelDownloader.isDownloading {
            downloadingStatus
        } else if llmEngine.isLoadingModel {
            loadingStatus
        } else if llmEngine.isLoaded {
            loadedModelMenu
        } else {
            unloadedModelControls
        }
    }

    private var downloadingStatus: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ProgressView(value: modelDownloader.downloadProgress)
                .progressViewStyle(.linear)
                .frame(width: 100)
            Text(modelDownloader.log)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    private var loadingStatus: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.75)
            Text("Loading Model")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    private var loadedModelMenu: some View {
        Menu {
            loadedModelMenuContent
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(llmEngine.isGenerating ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(llmEngine.isGenerating ? "Processing" : "Ready")
                    .font(.caption)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                liquidRoundedBackground(cornerRadius: 12)
            }
            .cornerRadius(12)
        }
        .disabled(llmEngine.isGenerating)
    }

    @ViewBuilder
    private var loadedModelMenuContent: some View {
        Section("Active Model") {
            ForEach(modelDownloader.availableModels, id: \.self) { model in
                Button {
                    modelDownloader.activeModelName = model
                } label: {
                    HStack {
                        Text(model)
                        if model == modelDownloader.activeModelName {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Section {
            Button(action: { showFileImporter = true }) {
                Label("Import New (.gguf)...", systemImage: "folder.badge.plus")
            }

            Button(action: onShowSettings) {
                Label("Settings", systemImage: "gear")
            }

            Button {
                llmEngine.stopGeneration()
                chatManager.createNewSession()
            } label: {
                Label("New Chat", systemImage: "plus.message")
            }

            Button(role: .destructive) {
                llmEngine.stopGeneration()
                chatManager.clearCurrentSession()
            } label: {
                Label("Clear Current Chat", systemImage: "trash")
            }

            Button(role: .destructive) {
                withAnimation {
                    llmEngine.unloadModel()
                }
            } label: {
                Label("Unload Engine", systemImage: "power")
            }
        }

        if !llmEngine.modelWarnings.isEmpty {
            Section("Model Warnings") {
                ForEach(llmEngine.modelWarnings, id: \.self) { warning in
                    Text(warning)
                }
            }
        }
    }

    private var unloadedModelControls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if modelDownloader.error != nil {
                Text(modelDownloader.log)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            HStack(spacing: 8) {
                Button(action: { showFileImporter = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16))
                }

                Menu {
                    ForEach(modelDownloader.remoteCatalog) { remoteModel in
                        Button {
                            modelDownloader.selectedRemoteModelID = remoteModel.id
                            modelDownloader.downloadModel()
                        } label: {
                            Label("Download \(remoteModel.displayName)", systemImage: "arrow.down.circle")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Download")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        liquidRoundedBackground(cornerRadius: 12)
                    }
                    .cornerRadius(12)
                }
            }

            Text("Selected: \(modelDownloader.selectedRemoteModel.displayName)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var messagesSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if currentMessages.isEmpty {
                        emptyStateView
                    }

                    ForEach(currentMessages) { message in
                        MessageBubble(
                            message: message,
                            isStreaming: llmEngine.isGenerating &&
                                message.id == currentMessages.last?.id &&
                                message.role == .assistant
                        )
                            .id(message.id)
                    }

                    if llmEngine.isGenerating {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding()
            }
            .id(chatManager.currentSession?.id)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: chatManager.currentSession?.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: llmEngine.isGenerating) { _, isGenerating in
                if isGenerating {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: chatManager.currentSession?.messages.last?.id) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatManager.currentSession?.messages.last?.content) { _, _ in
                if llmEngine.isGenerating {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .onChange(of: chatManager.currentSession?.id) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("EliAI")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.blue.opacity(0.5))
                .padding(.top, 40)

            if modelDownloader.isDownloading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(modelDownloader.log)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if !llmEngine.isLoaded {
                Text("No model loaded.")
                    .font(.caption)
                    .foregroundColor(.gray)

                if !modelDownloader.availableModels.isEmpty {
                    Menu {
                        ForEach(modelDownloader.availableModels, id: \.self) { model in
                            Button(model) {
                                modelDownloader.activeModelName = model
                            }
                        }
                    } label: {
                        Label("Select from Library (\(modelDownloader.availableModels.count))", systemImage: "books.vertical")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                    }
                }

                Text("Download or import a .gguf model to start.")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.top, 2)
            } else {
                Text("How can I help you today?")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var inputSection: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.25))
            HStack(alignment: .bottom) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        liquidRoundedBackground(cornerRadius: 22)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .lineLimit(1 ... 5)
                    .disabled(!llmEngine.isLoaded || llmEngine.isGenerating || llmEngine.isLoadingModel)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue.opacity(inputText.isEmpty ? 0.4 : 1.0))
                }
                .padding(5)
                .background {
                    liquidCircleBackground()
                }
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                .disabled(inputText.isEmpty || !llmEngine.isLoaded || llmEngine.isGenerating || llmEngine.isLoadingModel)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, (isCollapsed ? 10 : 24) + keyboardLift)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.04))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(colorScheme == .light ? 0.35 : 0.16), lineWidth: 0.5)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var safeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0
    }

    private var keyboardLift: CGFloat {
        guard !isCollapsed else { return 0 }
        return max(0, keyboardHeight - safeAreaBottomInset)
    }

    private func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        let screenHeight = UIScreen.main.bounds.height
        return max(0, screenHeight - endFrame.minY)
    }

    private func keyboardAnimation(for notification: Notification) -> Animation {
        if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
            return .easeOut(duration: duration)
        }
        return .easeOut(duration: 0.25)
    }

    private var chatPanelBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.white.opacity(colorScheme == .light ? 0.16 : 0.05))
            .overlay(colorScheme == .light ? Color.black.opacity(0.06) : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(colorScheme == .light ? 0.42 : 0.20), lineWidth: 0.6)
            )
            .overlay(
                Rectangle()
                    .stroke(Color.black.opacity(colorScheme == .light ? 0.08 : 0.25), lineWidth: 0.35)
            )
            .ignoresSafeArea()
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        AppLogger.debug("User message submitted.", category: .ui)

        if chatManager.currentSession == nil {
            chatManager.createNewSession()
        }

        let userMessage = ChatMessage(role: .user, content: inputText)
        chatManager.addMessage(userMessage)
        inputText = ""

        Task {
            await runAgentLoop()
        }
    }

    private func runAgentLoop() async {
        var keepGenerating = true
        var steps = 0
        let maxSteps = 4

        while keepGenerating && steps < maxSteps {
            steps += 1
            keepGenerating = false

            var fullResponse = ""
            var assistantMessage = ChatMessage(role: .assistant, content: "")
            chatManager.addMessage(assistantMessage)

            let history = chatManager.currentSession?.messages.dropLast()
            let stream = llmEngine.generate(messages: Array(history ?? []))

            for await token in stream {
                fullResponse += token
                await MainActor.run {
                    assistantMessage.content = fullResponse
                    chatManager.updateLastMessage(assistantMessage, persist: false)
                }
            }

            await MainActor.run {
                assistantMessage.content = fullResponse
                chatManager.updateLastMessage(assistantMessage)
                if fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chatManager.removeMessage(id: assistantMessage.id)
                }
            }

            if let toolOutput = await agentManager.processToolCalls(in: fullResponse) {
                let toolMessage = ChatMessage(role: .tool, content: toolOutput)
                chatManager.addMessage(toolMessage)
                keepGenerating = true
            }

            if let session = chatManager.currentSession {
                chatManager.saveSession(session)
            }
        }

        if steps >= maxSteps {
            let warning = ChatMessage(
                role: .system,
                content: "Agent loop reached safety step limit. Please continue with a follow-up prompt."
            )
            chatManager.addMessage(warning)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func liquidRoundedBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.48), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func liquidCircleBackground() -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}
