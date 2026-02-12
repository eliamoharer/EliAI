import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
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
                
                Text(message.content)
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
}
