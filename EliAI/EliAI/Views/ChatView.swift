import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    @Environment(ChatManager.self) var chatManager
    @Environment(LLMEngine.self) var llmEngine
    @Environment(AgentManager.self) var agentManager
    @Environment(ModelDownloader.self) var modelDownloader
    @Environment(ChatCoordinator.self) var chatCoordinator
    
    var onShowSettings: () -> Void = {}
    var isCollapsed: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showFileImporter = false
    @State private var keyboardOverlap: CGFloat = 0
    @State private var scrollRequestID: Int = 0
    @State var activePhoneMode: PhoneMode? = nil
    @State private var showModeMenu = false
    private let bottomAnchorID = "chatBottomAnchor"

    private var currentMessages: [ChatMessage] {
        chatManager.currentSession?.messages ?? []
    }

    private var canSendMessage: Bool {
        let hasMeaningfulInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasMeaningfulInput &&
            llmEngine.isLoaded &&
            !llmEngine.isGenerating &&
            !llmEngine.isLoadingModel &&
            !chatCoordinator.isAgentLoopRunning
    }

    private var canStopGeneration: Bool {
        llmEngine.isGenerating || chatCoordinator.isAgentLoopRunning
    }

    private var composerButtonEnabled: Bool {
        canStopGeneration || canSendMessage
    }

    private var canRegenerateLastReply: Bool {
        guard let messages = chatManager.currentSession?.messages else {
            return false
        }

        return llmEngine.isLoaded &&
            !llmEngine.isGenerating &&
            !llmEngine.isLoadingModel &&
            !chatCoordinator.isAgentLoopRunning &&
            messages.contains(where: { $0.role == .user })
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
            handleKeyboardFrameChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            handleKeyboardFrameChange(notification, forceHide: true)
        }
    }

    private var topGrabber: some View {
        Capsule()
            .fill(Color.primary.opacity(0.22))
            .frame(width: isCollapsed ? 56 : 42, height: 5)
            .padding(.top, isCollapsed ? 10 : 8)
            .padding(.bottom, isCollapsed ? 8 : 6)
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
                activePhoneMode = nil
            } label: {
                Label("New Chat", systemImage: "plus.message")
            }

            Button {
                regenerateLastReply()
            } label: {
                Label("Regenerate Last Reply", systemImage: "arrow.clockwise")
            }
            .disabled(!canRegenerateLastReply)

            Button(role: .destructive) {
                llmEngine.stopGeneration()
                chatManager.clearCurrentSession()
                activePhoneMode = nil
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
            .onAppear {
                DispatchQueue.main.async {
                    scrollToBottomStabilized(proxy: proxy, animated: false)
                }
            }
            .onChange(of: chatManager.currentSession?.messages.count) { _, _ in
                scrollToBottomStabilized(proxy: proxy, animated: false)
            }
            .onChange(of: llmEngine.isGenerating) { _, _ in
                scrollToBottomStabilized(proxy: proxy, animated: false)
            }
            .onChange(of: chatManager.currentSession?.messages.last?.content) { _, _ in
                if llmEngine.isGenerating {
                    scrollToBottomStabilized(proxy: proxy, animated: false)
                }
            }
            .onChange(of: chatManager.currentSession?.id) { _, _ in
                scrollToBottomStabilized(proxy: proxy, animated: false)
            }
            .onChange(of: scrollRequestID) { _, _ in
                scrollToBottomStabilized(proxy: proxy, animated: true)
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

            composerRow
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, inputBottomInset)
        }
        .background(inputSectionBackground)
    }

    private var composerRow: some View {
        let modeColor = activePhoneMode?.accentColor
        let hasMode = modeColor != nil

        return HStack(alignment: .bottom) {
            plusButton(modeColor: modeColor, hasMode: hasMode)
            composerTextField(modeColor: modeColor, hasMode: hasMode)
            sendButton(modeColor: modeColor, hasMode: hasMode)
        }
    }

    private func plusButton(modeColor: Color?, hasMode: Bool) -> some View {
        let iconName = hasMode ? "xmark" : "plus"
        let iconColor: Color = hasMode ? modeColor! : .primary.opacity(0.7)
        let strokeColor: Color = hasMode ? modeColor!.opacity(0.6) : Color.white.opacity(0.35)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if hasMode {
                    activePhoneMode = nil
                } else {
                    showModeMenu.toggle()
                }
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
        }
        .frame(width: 42, height: 42)
        .background { liquidCircleBackground() }
        .overlay(Circle().stroke(strokeColor, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .popover(isPresented: $showModeMenu) {
            phoneModeMenuContent
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func composerTextField(modeColor: Color?, hasMode: Bool) -> some View {
        let strokeColor: Color = hasMode ? modeColor!.opacity(0.5) : Color.white.opacity(0.35)
        let isDisabled = !llmEngine.isLoaded || llmEngine.isGenerating || llmEngine.isLoadingModel || chatCoordinator.isAgentLoopRunning

        TextField("Message...", text: $inputText, axis: .vertical)
            .focused($isInputFocused)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background { composerTextFieldBackground(modeColor: modeColor) }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.8)
            )
            .lineLimit(1 ... 6)
            .disabled(isDisabled)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activePhoneMode)
    }

    @ViewBuilder
    private func composerTextFieldBackground(modeColor: Color?) -> some View {
        if let color = modeColor {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                )
        } else {
            liquidRoundedBackground(cornerRadius: 22)
        }
    }

    private func sendButton(modeColor: Color?, hasMode: Bool) -> some View {
        let iconName = canStopGeneration ? "stop.circle.fill" : "arrow.up.circle.fill"
        let baseColor: Color = hasMode ? modeColor! : Color.blue
        let iconColor: Color = canStopGeneration
            ? Color.red.opacity(0.92)
            : baseColor.opacity(canSendMessage ? 1.0 : 0.4)

        return Button(action: handleComposerPrimaryAction) {
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(iconColor)
        }
        .padding(5)
        .background { liquidCircleBackground() }
        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .disabled(!composerButtonEnabled)
    }

    private var inputSectionBackground: some View {
        let overlayColor: Color = colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.04)
        let strokeColor = Color.white.opacity(colorScheme == .light ? 0.35 : 0.16)

        return Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(overlayColor)
            .overlay(Rectangle().stroke(strokeColor, lineWidth: 0.5))
            .ignoresSafeArea(edges: .bottom)
    }

    private var phoneModeMenuContent: some View {
        VStack(spacing: 4) {
            ForEach(PhoneMode.allCases) { mode in
                phoneModeMenuRow(mode: mode)
            }
        }
        .padding(12)
        .frame(width: 200)
    }

    private func phoneModeMenuRow(mode: PhoneMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                activePhoneMode = mode
                showModeMenu = false
            }
            Task {
                await agentManager.phoneModeManager.preauthorize(for: mode)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(mode.accentColor)
                    .frame(width: 28)
                Text(mode.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(mode.accentColor.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var inputBottomInset: CGFloat {
        if isCollapsed {
            return 24
        }
        if keyboardOverlap > 0 {
            return keyboardOverlap + 10
        }
        return 24
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
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !chatCoordinator.isAgentLoopRunning else { return }
        AppLogger.debug("User message submitted.", category: .ui)

        let input = inputText
        inputText = ""
        scrollRequestID &+= 1

        Task {
            await chatCoordinator.sendMessage(input, phoneMode: activePhoneMode)
        }
    }

    private func handleComposerPrimaryAction() {
        if canStopGeneration {
            chatCoordinator.stopGeneration()
            return
        }
        sendMessage()
    }

    private func regenerateLastReply() {
        guard canRegenerateLastReply else { return }

        AppLogger.info("Regenerating assistant reply from last user prompt.", category: .ui)
        scrollRequestID &+= 1

        Task {
            await chatCoordinator.regenerateLastReply(phoneMode: activePhoneMode)
        }
    }

    private func shouldAttemptModelRecovery(for error: String) -> Bool {
        let normalized = error.lowercased()
        return normalized.contains("timeout") ||
            normalized.contains("unresponsive") ||
            normalized.contains("no output")
    }

    private func hasToolOutputAfterLatestUser(in messages: [ChatMessage]) -> Bool {
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }) else {
            return false
        }
        guard userIndex + 1 < messages.count else {
            return false
        }
        return messages[(userIndex + 1)...].contains(where: { $0.role == .tool })
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

    private func scrollToBottomStabilized(proxy: ScrollViewProxy, animated: Bool) {
        scrollToBottom(proxy: proxy, animated: animated)
        // Single stabilization attempt after initial scroll
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(AppConstants.UI.scrollStabilizationDelaySeconds * 1_000_000_000))
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func handleKeyboardFrameChange(_ notification: Notification, forceHide: Bool = false) {
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRawValue = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? UIView.AnimationCurve.easeInOut.rawValue
        let curve = UIView.AnimationCurve(rawValue: curveRawValue) ?? .easeInOut

        let overlap: CGFloat
        if forceHide {
            overlap = 0
        } else if let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            overlap = calculateKeyboardOverlap(for: frameValue)
        } else {
            overlap = 0
        }

        let target = max(0, overlap)
        guard abs(target - keyboardOverlap) > 0.5 else {
            return
        }

        withAnimation(animation(for: curve, duration: duration)) {
            keyboardOverlap = target
        }
    }

    private func calculateKeyboardOverlap(for keyboardFrame: CGRect) -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let keyWindow = windowScene.windows.first(where: \.isKeyWindow) else {
            return 0
        }

        let localFrame = keyWindow.convert(keyboardFrame, from: nil)
        let overlap = keyWindow.bounds.maxY - localFrame.minY
        return max(0, overlap)
    }

    private func animation(for curve: UIView.AnimationCurve, duration: Double) -> Animation {
        switch curve {
        case .easeInOut:
            return .easeInOut(duration: duration)
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .linear:
            return .linear(duration: duration)
        @unknown default:
            return .easeOut(duration: duration)
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
