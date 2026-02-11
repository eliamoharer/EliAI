import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading) {
                if message.role == .tool {
                    Text("🛠️ Tool Output:")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Text(message.content)
                    .padding(10)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(12)
            }
            
            if message.role != .user {
                Spacer()
            }
        }
    }
    
    var backgroundColor: Color {
        switch message.role {
        case .user: return Color.blue
        case .assistant: return Color(UIColor.secondarySystemBackground)
        case .system: return Color.gray.opacity(0.2)
        case .tool: return Color.orange.opacity(0.2)
        }
    }
    
    var foregroundColor: Color {
        switch message.role {
        case .user: return .white
        default: return .primary
        }
    }
}
