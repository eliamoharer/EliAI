import SwiftUI

struct ChatView: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var llmEngine: LLMEngine
    @ObservedObject var agentManager: AgentManager
    
    @State private var inputText: String = ""
    @State private var isInputFocused: Bool = false
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Text(chatManager.currentSession?.title ?? "New Chat")
                    .font(.headline)
                Spacer()
                if llmEngine.isLoaded {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                } else {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                }
            }
            .padding()
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(chatManager.currentSession?.messages ?? []) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if llmEngine.isGenerating {
                            HStack {
                                ProgressView()
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: chatManager.currentSession?.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            // Input Area
            HStack {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(!llmEngine.isLoaded || llmEngine.isGenerating)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(inputText.isEmpty || !llmEngine.isLoaded || llmEngine.isGenerating)
            }
            .padding()
        }
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        
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
                // Update implementation to stream updates to the UI
                // In a real app, this update logic needs to be efficient
                // For now, we update the whole message
                DispatchQueue.main.async {
                    assistantMessage.content = fullResponse
                    // Update the last message in the session
                    // This is slightly inefficient but works for MVP
                    if var session = chatManager.currentSession {
                        session.messages[session.messages.count - 1] = assistantMessage
                        chatManager.currentSession = session 
                    }
                }
            }
            
            // 3. Tool Check (Agentic behavior)
            if let toolOutput = await agentManager.processToolCalls(in: fullResponse) {
                // If tools were called, we might want to feed that back to the LLM
                // For this MVP, we just append the tool output as a system/tool message
                let toolMessage = ChatMessage(role: .tool, content: toolOutput)
                chatManager.addMessage(toolMessage)
            }
            
            chatManager.saveSession(chatManager.currentSession!)
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
