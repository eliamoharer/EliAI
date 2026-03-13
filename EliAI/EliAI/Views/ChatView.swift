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
    @State private var keyboardOverlap: CGFloat = 0
    @State private var scrollRequestID: Int = 0
    @State private var isAgentLoopRunning = false
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
            !isAgentLoopRunning
    }

    private var canStopGeneration: Bool {
        llmEngine.isGenerating || isAgentLoopRunning
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
            !isAgentLoopRunning &&
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
        let isDisabled = !llmEngine.isLoaded || llmEngine.isGenerating || llmEngine.isLoadingModel || isAgentLoopRunning

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
        guard !trimmedInput.isEmpty, !isAgentLoopRunning else { return }
        AppLogger.debug("User message submitted.", category: .ui)

        if chatManager.currentSession == nil {
            chatManager.createNewSession()
        }

        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        chatManager.addMessage(userMessage)
        inputText = ""
        scrollRequestID &+= 1
        isAgentLoopRunning = true

        Task {
            await runAgentLoop()
            await MainActor.run {
                isAgentLoopRunning = false
            }
        }
    }

    private func handleComposerPrimaryAction() {
        if canStopGeneration {
            llmEngine.stopGeneration()
            return
        }
        sendMessage()
    }

    private func regenerateLastReply() {
        guard canRegenerateLastReply else { return }
        guard let session = chatManager.currentSession,
              let lastUserIndex = session.messages.lastIndex(where: { $0.role == .user }) else {
            return
        }

        AppLogger.info("Regenerating assistant reply from last user prompt.", category: .ui)
        llmEngine.stopGeneration()
        chatManager.trimCurrentSession(upToIncluding: lastUserIndex)
        scrollRequestID &+= 1
        isAgentLoopRunning = true

        Task {
            await runAgentLoop()
            await MainActor.run {
                isAgentLoopRunning = false
            }
        }
    }

    private func runAgentLoop() async {
        var keepGenerating = true
        var steps = 0
        let maxSteps = AppConstants.AgentLoop.maxSteps
        var recoveryAttempts = 0
        var enforcedToolRetryUsed = false
        var forceToolCallNextStep = false

        while keepGenerating && steps < maxSteps {
            steps += 1
            keepGenerating = false

            var fullResponse = ""
            var assistantMessage = ChatMessage(role: .assistant, content: "")
            chatManager.addMessage(assistantMessage)

            var history = Array(chatManager.currentSession?.messages.dropLast() ?? ArraySlice<ChatMessage>())
            let latestUserPrompt = history.last(where: { $0.role == .user })?.content ?? ""
            let hasToolResultAfterLatestUser = hasToolOutputAfterLatestUser(in: history)

            // Inject a nudge into history instead of replacing the system prompt,
            // so the model still sees full tool definitions.
            if forceToolCallNextStep {
                history.append(ChatMessage(
                    role: .system,
                    content: "You MUST respond with a <tool_call> block for this request."
                ))
            }
            let stream = llmEngine.generate(messages: history, phoneMode: activePhoneMode)
            forceToolCallNextStep = false

            for await token in stream {
                fullResponse += token
                await MainActor.run {
                    assistantMessage.content = fullResponse
                    chatManager.updateLastMessage(assistantMessage, persist: false)
                }
            }

            if !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let error = llmEngine.generationError,
               shouldAttemptModelRecovery(for: error),
               recoveryAttempts < AppConstants.LLMEngine.maxRecoveryAttempts {
                recoveryAttempts += 1
                AppLogger.warning(
                    "Partial generation ended with recoverable error. Reloading model (attempt \(recoveryAttempts)/\(AppConstants.LLMEngine.maxRecoveryAttempts))...",
                    category: .inference
                )

                let recovered = await llmEngine.reloadCurrentModel()
                if recovered {
                    await MainActor.run {
                        llmEngine.generationError = nil
                        chatManager.removeMessage(id: assistantMessage.id)
                    }
                    keepGenerating = true
                    continue
                }
            }

            if fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if llmEngine.lastGenerationWasCancelled {
                    await MainActor.run {
                        AppLogger.debug("Generation ended with cancellation; removing empty assistant placeholder.", category: .inference)
                        chatManager.removeMessage(id: assistantMessage.id)
                    }
                    break
                }

                // Attempt recovery if model error detected
                if let error = llmEngine.generationError, 
                   shouldAttemptModelRecovery(for: error),
                   recoveryAttempts < AppConstants.LLMEngine.maxRecoveryAttempts {
                    recoveryAttempts += 1
                    await MainActor.run {
                        chatManager.removeMessage(id: assistantMessage.id)
                    }
                    AppLogger.warning("Generation error detected. Reloading model (attempt \(recoveryAttempts)/\(AppConstants.LLMEngine.maxRecoveryAttempts))...", category: .inference)

                    let recovered = await llmEngine.reloadCurrentModel()

                    if recovered {
                        // Clear error state before retry
                        await MainActor.run {
                            llmEngine.generationError = nil
                        }
                        keepGenerating = true
                        continue
                    } else {
                        AppLogger.error("Model recovery failed. Reload did not succeed.", category: .inference)
                    }
                }

                // If we've exhausted recovery attempts or no error was detected, show error message
                let fallbackMessage = llmEngine.generationError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (llmEngine.generationError ?? "I couldn't generate a response. Please try again.")
                    : "I couldn't generate a response. Please try again."

                await MainActor.run {
                    AppLogger.error(
                        "Generation produced empty output. error=\(llmEngine.generationError ?? "nil"), recoveryAttempts=\(recoveryAttempts)",
                        category: .inference
                    )
                    assistantMessage.content = fallbackMessage
                    chatManager.updateLastMessage(assistantMessage)
                }
            } else {
                // Success - reset recovery attempts
                recoveryAttempts = 0
                var finalResponse = fullResponse
                if let error = llmEngine.generationError,
                   shouldAttemptModelRecovery(for: error) {
                    finalResponse += "\n\n[Response may be incomplete: \(error)]"
                }
                await MainActor.run {
                    assistantMessage.content = finalResponse
                    chatManager.updateLastMessage(assistantMessage)
                }
            }

            if fullResponse.contains("<tool_call>") && !fullResponse.contains("</tool_call>") {
                fullResponse += "\n</tool_call>"
                await MainActor.run {
                    assistantMessage.content = fullResponse
                    chatManager.updateLastMessage(assistantMessage)
                }
            }

            let toolOutput = await agentManager.processToolCalls(in: fullResponse)
            if toolOutput == nil,
               !enforcedToolRetryUsed,
               !hasToolResultAfterLatestUser,
               requiresToolCall(for: latestUserPrompt),
               !containsToolInvocation(in: fullResponse) {
                enforcedToolRetryUsed = true
                forceToolCallNextStep = true
                await MainActor.run {
                    chatManager.removeMessage(id: assistantMessage.id)
                }
                keepGenerating = true
                continue
            }

            if let toolOutput {
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

    private func shouldAttemptModelRecovery(for error: String) -> Bool {
        let normalized = error.lowercased()
        return normalized.contains("timeout") ||
            normalized.contains("unresponsive") ||
            normalized.contains("no output")
    }

    private func requiresToolCall(for userPrompt: String) -> Bool {
        let text = userPrompt.lowercased()

        if text.contains("remind me") || text.contains("set a reminder") || text.contains("set reminder") {
            return true
        }

        if let mode = activePhoneMode {
            switch mode {
            case .openApp:
                let locationWords = ["find", "nearest", "near me", "close to", "where is", "show me", "directions", "navigate", "open"]
                if locationWords.contains(where: { text.contains($0) }) { return true }
            case .reminders:
                let reminderWords = ["remind", "reminder", "create", "add", "set", "list"]
                if reminderWords.contains(where: { text.contains($0) }) { return true }
            case .health:
                let healthWords = ["log", "track", "record", "add", "drank", "slept", "water", "coffee", "sleep", "steps", "walked"]
                if healthWords.contains(where: { text.contains($0) }) { return true }
            case .calendar:
                let calWords = ["event", "meeting", "schedule", "appointment", "add", "create", "list", "upcoming"]
                if calWords.contains(where: { text.contains($0) }) { return true }
            case .shortcuts:
                let shortcutWords = ["run", "execute", "launch", "shortcut", "save", "list"]
                if shortcutWords.contains(where: { text.contains($0) }) { return true }
            }
        }

        let actions = [
            "create", "write", "save", "store", "read", "open", "list",
            "show", "delete", "remove", "append", "update", "recall",
            "remember", "search", "find", "remind", "schedule",
            "complete", "finish", "done", "log", "run", "launch"
        ]
        let targets = [
            "file", "files", "folder", "directory", "memory", "memories",
            "task", "tasks", "note", "notes", "reminder", "reminders",
            "event", "calendar", "shortcut", "shortcuts", "water", "sleep",
            "caffeine", "steps", "health", "maps", "directions"
        ]

        return actions.contains(where: { text.contains($0) }) &&
               targets.contains(where: { text.contains($0) })
    }

    private func containsToolInvocation(in response: String) -> Bool {
        if response.contains("<tool_call>") {
            return true
        }
        var knownTools = [
            "create_file", "read_file", "list_files",
            "create_memory", "recall_memory", "list_memories", "search_memory",
            "create_task", "list_tasks", "complete_task"
        ]
        if let mode = activePhoneMode {
            knownTools.append(contentsOf: mode.toolNames)
        }
        let lowered = response.lowercased()
        if lowered.contains("\"name\"") && knownTools.contains(where: { lowered.contains($0) }) {
            return true
        }
        return false
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
