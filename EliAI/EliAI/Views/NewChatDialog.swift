import SwiftUI

struct NewChatDialog: View {
    @Binding var isPresented: Bool
    @State private var chatName: String = ""
    var onCreate: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Chat")
                .font(.headline)
            
            TextField("Chat Name", text: $chatName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .padding()
                
                Button("Create") {
                    onCreate(chatName.isEmpty ? "New Chat" : chatName)
                    isPresented = false
                }
                .padding()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
    }
}
