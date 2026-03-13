import Foundation
import Observation

enum AgentState: Equatable {
    case idle
    case generating
    case recovering(attempt: Int)
    case executingTool
    case error(String)
}

@Observable
@MainActor
class ChatCoordinator {
    let chatManager: ChatManager
    let llmEngine: LLMEngine
    let agentManager: AgentManager

    var state: AgentState = .idle
    var isAgentLoopRunning: Bool {
        if case .idle = state { return false }
        if case .error = state { return false }
        return true
    }

    init(chatManager: ChatManager, llmEngine: LLMEngine, agentManager: AgentManager) {
        self.chatManager = chatManager
        self.llmEngine = llmEngine
        self.agentManager = agentManager
    }

    func sendMessage(_ text: String, phoneMode: PhoneMode?) async {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !isAgentLoopRunning else { return }

        if chatManager.currentSession == nil {
            chatManager.createNewSession()
        }

        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        chatManager.addMessage(userMessage)

        await runAgentLoop(phoneMode: phoneMode)
    }

    func regenerateLastReply(phoneMode: PhoneMode?) async {
        guard let session = chatManager.currentSession,
              let lastUserIndex = session.messages.lastIndex(where: { $0.role == .user }) else {
            return
        }

        llmEngine.stopGeneration()
        chatManager.trimCurrentSession(upToIncluding: lastUserIndex)

        await runAgentLoop(phoneMode: phoneMode)
    }

    func stopGeneration() {
        llmEngine.stopGeneration()
        state = .idle
    }

    private func runAgentLoop(phoneMode: PhoneMode?) async {
        var keepGenerating = true
        var steps = 0
        let maxSteps = AppConstants.AgentLoop.maxSteps
        var recoveryAttempts = 0

        while keepGenerating && steps < maxSteps {
            steps += 1
            keepGenerating = false

            state = .generating

            var fullResponse = ""
            var assistantMessage = ChatMessage(role: .assistant, content: "")
            chatManager.addMessage(assistantMessage)

            let history = Array(chatManager.currentSession?.messages.dropLast() ?? ArraySlice<ChatMessage>())

            let stream = llmEngine.generate(messages: history, toolPrompt: agentManager.toolPromptString, phoneMode: phoneMode)

            for await token in stream {
                fullResponse += token
                assistantMessage.content = fullResponse
                chatManager.updateLastMessage(assistantMessage, persist: false)
            }

            if !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let error = llmEngine.generationError,
               shouldAttemptModelRecovery(for: error),
               recoveryAttempts < AppConstants.LLMEngine.maxRecoveryAttempts {
                recoveryAttempts += 1
                state = .recovering(attempt: recoveryAttempts)
                
                let recovered = await llmEngine.reloadCurrentModel()
                if recovered {
                    llmEngine.generationError = nil
                    chatManager.removeMessage(id: assistantMessage.id)
                    keepGenerating = true
                    continue
                }
            }

            if fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if llmEngine.lastGenerationWasCancelled {
                    chatManager.removeMessage(id: assistantMessage.id)
                    state = .idle
                    break
                }

                if let error = llmEngine.generationError,
                   shouldAttemptModelRecovery(for: error),
                   recoveryAttempts < AppConstants.LLMEngine.maxRecoveryAttempts {
                    recoveryAttempts += 1
                    state = .recovering(attempt: recoveryAttempts)
                    chatManager.removeMessage(id: assistantMessage.id)
                    
                    let recovered = await llmEngine.reloadCurrentModel()
                    if recovered {
                        llmEngine.generationError = nil
                        keepGenerating = true
                        continue
                    }
                }

                let fallbackMessage = llmEngine.generationError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (llmEngine.generationError ?? "I couldn't generate a response. Please try again.")
                    : "I couldn't generate a response. Please try again."

                assistantMessage.content = fallbackMessage
                chatManager.updateLastMessage(assistantMessage)
                state = .error(fallbackMessage)
            } else {
                recoveryAttempts = 0
                var finalResponse = fullResponse
                if let error = llmEngine.generationError,
                   shouldAttemptModelRecovery(for: error) {
                    finalResponse += "\n\n[Response may be incomplete: \(error)]"
                }
                assistantMessage.content = finalResponse
                chatManager.updateLastMessage(assistantMessage)
            }

            if fullResponse.contains("<tool_call>") && !fullResponse.contains("</tool_call>") {
                fullResponse += "\n</tool_call>"
                assistantMessage.content = fullResponse
                chatManager.updateLastMessage(assistantMessage)
            }

            state = .executingTool
            let toolOutput = await agentManager.processToolCalls(in: fullResponse)
            
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
            state = .error("Loop limit reached.")
        } else if case .executingTool = state {
            state = .idle
        } else if case .generating = state {
            state = .idle
        }
    }

    private func shouldAttemptModelRecovery(for error: String) -> Bool {
        let normalized = error.lowercased()
        return normalized.contains("timeout") ||
            normalized.contains("unresponsive") ||
            normalized.contains("no output")
    }
}