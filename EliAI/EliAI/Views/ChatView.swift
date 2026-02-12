import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    var chatManager: ChatManager
    var llmEngine: LLMEngine
    var agentManager: AgentManager
    // Pass modelDownloader to observe progress
    var modelDownloader: ModelDownloader
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showFileImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
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
                } else if llmEngine.isLoaded {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Ready")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
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
                            
                            Button(action: {
                                modelDownloader.downloadModel()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Download")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(.thinMaterial)
            
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
                                     Text("Download or import a .gguf model to start.")
                                        .font(.caption2)
                                        .foregroundColor(.gray.opacity(0.8))
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
                .onChange(of: chatManager.currentSession?.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: llmEngine.isGenerating) { isGenerating in
                    if isGenerating { scrollToBottom(proxy: proxy) }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .bottom) {
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .focused($isInputFocused)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                        .disabled(!llmEngine.isLoaded || llmEngine.isGenerating)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.isEmpty ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty || !llmEngine.isLoaded || llmEngine.isGenerating)
                }
                // Removed extra padding to sit flush against safe area if needed
                // But usually we want some padding from edges.
                // The critical part is observing keyboard or safe area.
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8) // Add some internal padding
                .background(.bar)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    modelDownloader.importLocalModel(from: url)
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        // Ensure a session exists
        if chatManager.currentSession == nil {
            chatManager.createNewSession()
        }
        
        // 1. User Message
        let userMessage = ChatMessage(role: .user, content: inputText)
        chatManager.addMessage(userMessage)
        let prompt = inputText
        inputText = ""
        
        // 2. Assistant Generation
        Task {
            var fullResponse = ""
            var assistantMessage = ChatMessage(role: .assistant, content: "")
            chatManager.addMessage(assistantMessage) // Add placeholder
            
            let stream = llmEngine.generate(prompt: prompt)
            
            for await token in stream {
                fullResponse += token
                DispatchQueue.main.async {
                    // Update local reference
                    assistantMessage.content = fullResponse
                    
                    // Update model safely
                    if var session = chatManager.currentSession, !session.messages.isEmpty {
                        let lastIndex = session.messages.count - 1
                        if lastIndex >= 0 {
                            session.messages[lastIndex] = assistantMessage
                            chatManager.currentSession = session
                        }
                    }
                }
            }
            
            // 3. Tool Check (Agentic behavior)
            if let toolOutput = await agentManager.processToolCalls(in: fullResponse) {
                let toolMessage = ChatMessage(role: .tool, content: toolOutput)
                chatManager.addMessage(toolMessage)
            }
            
            if let session = chatManager.currentSession {
                chatManager.saveSession(session)
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
}
