import SwiftUI

struct SettingsView: View {
    @State private var modelPath: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Model Information")) {
                Text("Model: HY-1.8B-2Bit-GGUF")
                Text("Status: Local & Private")
                    .foregroundColor(.green)
            }
            
            Section(header: Text("Storage")) {
                Button("Clear Chat History") {
                    // Implement clear history logic
                }
                .foregroundColor(.red)
            }
            
            Section(header: Text("About")) {
                Text("EliAI v1.0")
                Text("Powered by llama.cpp & HunYuan")
            }
        }
        .navigationTitle("Settings")
    }
}
