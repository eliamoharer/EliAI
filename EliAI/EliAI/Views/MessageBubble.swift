import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    @State private var isThinkingVisible = false
    
    var body: some View {
        let parsed = parseThinkingSections(from: message.content)
        let visibleText = message.role == .assistant ? parsed.visible : message.content

        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
            } else {
                // Assistant Icon
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)
                    .padding(6)
                    .background(Circle().fill(Color.blue.opacity(0.1)))
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .tool {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .font(.caption2)
                        Text("Tool Output")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.orange)
                }

                if message.role == .assistant, !parsed.thinking.isEmpty {
                    DisclosureGroup(isExpanded: $isThinkingVisible) {
                        Text(parsed.thinking)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Text(isThinkingVisible ? "Hide Thinking" : "Show Thinking")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
                 
                Text(visibleText.isEmpty ? " " : visibleText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            
            if message.role != .user {
                Spacer()
            } else {
                // User Icon (optional, or just avatar)
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.gray)
            }
        }
    }
    
    var backgroundColor: Color {
        switch message.role {
        case .user: return Color.blue
        case .assistant: return Color(UIColor.secondarySystemBackground)
        case .system: return Color.yellow.opacity(0.2)
        case .tool: return Color.orange.opacity(0.1)
        }
    }
    
    var foregroundColor: Color {
        switch message.role {
        case .user: return .white
        default: return .primary
        }
    }

    private func parseThinkingSections(from text: String) -> (visible: String, thinking: String) {
        var visible = ""
        var thinkingParts: [String] = []
        var cursor = text.startIndex

        while let startRange = text[cursor...].range(of: "<think>") {
            visible += String(text[cursor..<startRange.lowerBound])
            let thinkingStart = startRange.upperBound

            if let endRange = text[thinkingStart...].range(of: "</think>") {
                let section = String(text[thinkingStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !section.isEmpty {
                    thinkingParts.append(section)
                }
                cursor = endRange.upperBound
            } else {
                let section = String(text[thinkingStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !section.isEmpty {
                    thinkingParts.append(section)
                }
                cursor = text.endIndex
                break
            }
        }

        if cursor < text.endIndex {
            visible += String(text[cursor...])
        }

        visible = visible
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let thinking = thinkingParts.joined(separator: "\n\n")
        return (visible, thinking)
    }
}
