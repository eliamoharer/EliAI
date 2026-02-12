import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    var chatManager: ChatManager
    var llmEngine: LLMEngine
    var agentManager: AgentManager
    // Pass modelDownloader to observe progress
    var modelDownloader: ModelDownloader
    var onShowSettings: () -> Void = {}
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showFileImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 42, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Header
            HStack {
                Text(chatManager.currentSession?.title ?? "EliAI")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                
                if modelDownloader.isDownloading {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: modelDownloader.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 100)
                        Text(modelDownloader.log)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                } else if llmEngine.isLoadingModel {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text("Loading Model")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else if llmEngine.isLoaded {
                    Menu {
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

                            Button {
                                onShowSettings()
                            } label: {
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
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(llmEngine.isGenerating ? Color.orange : Color.green).frame(width: 8, height: 8)
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
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        if modelDownloader.error != nil {
                            Text(modelDownloader.log)
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                showFileImporter = true
                            }) {
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
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                    )
            )
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Introduction / Empty State / Loading State
                        if (chatManager.currentSession?.messages.isEmpty ?? true) {
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
                        
                        ForEach(chatManager.currentSession?.messages ?? []) { message in
                            MessageBubble(message: message)
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
                    }
                    .padding()
                }
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: chatManager.currentSession?.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: llmEngine.isGenerating) { _, isGenerating in
                    if isGenerating { scrollToBottom(proxy: proxy) }
                }
            }
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.02))
            )
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
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
                        .lineLimit(1...5)
                        .disabled(!llmEngine.isLoaded || llmEngine.isGenerating || llmEngine.isLoadingModel)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.isEmpty ? .gray : .blue)
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
                .padding(.bottom, 10)
            }
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .bottom)
            )
        }
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
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        AppLogger.debug("User message submitted.", category: .ui)
        
        // Ensure a session exists
        if chatManager.currentSession == nil {
            chatManager.createNewSession()
        }
        
        // 1. User Message
        let userMessage = ChatMessage(role: .user, content: inputText)
        chatManager.addMessage(userMessage)
        inputText = ""
        
        // Start Agent Loop
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
            keepGenerating = false // Default to stop unless tool triggers continuation
            
            // 2. Assistant Generation
            var fullResponse = ""
            var assistantMessage = ChatMessage(role: .assistant, content: "")
            chatManager.addMessage(assistantMessage) // Add placeholder
            
            // Generate using FULL history
            let history = chatManager.currentSession?.messages.dropLast() // Exclude the placeholder we just added
            let stream = llmEngine.generate(messages: Array(history ?? []))
            
            for await token in stream {
                fullResponse += token

                await MainActor.run {
                    assistantMessage.content = fullResponse
                    updateLastMessage(with: assistantMessage)
                }
            }
            
            // Final update
            await MainActor.run {
                assistantMessage.content = fullResponse
                updateLastMessage(with: assistantMessage)
            }
            
            // 3. Tool Check (Agentic behavior)
            if let toolOutput = await agentManager.processToolCalls(in: fullResponse) {
                // Add tool output to history
                let toolMessage = ChatMessage(role: .tool, content: toolOutput)
                chatManager.addMessage(toolMessage)
                
                // Loop continues to let the model interpret the tool output
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
    
    private func updateLastMessage(with message: ChatMessage) {
        if var session = chatManager.currentSession {
            if !session.messages.isEmpty {
                session.messages[session.messages.count - 1] = message
                chatManager.currentSession = session
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = chatManager.currentSession?.messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func liquidRoundedBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func liquidCircleBackground() -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }
}
