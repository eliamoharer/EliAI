import SwiftUI

struct FileDetailView: View {
    let fileItem: FileItem
    @State private var content: String = ""
    @State private var isEditing: Bool = false
    @State private var chatSessionPreview: ChatSession?
    
    var body: some View {
        VStack {
            if isEditing {
                TextEditor(text: $content)
                    .padding()
            } else if let session = chatSessionPreview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("\(session.messages.count) messages")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(session.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(message.content)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(fileItem.name)
        .navigationBarItems(trailing: Button(isEditing ? "Save" : "Edit") {
            if isEditing {
                saveFile()
            }
            isEditing.toggle()
        })
        .onAppear {
            loadFile()
        }
    }
    
    private func loadFile() {
        do {
            let raw = try String(contentsOf: fileItem.path, encoding: .utf8)

            if fileItem.name.hasSuffix(".json"),
               let data = raw.data(using: .utf8),
               let session = try? JSONDecoder().decode(ChatSession.self, from: data) {
                chatSessionPreview = session
                content = prettyPrintedJSONString(from: data) ?? raw
            } else {
                chatSessionPreview = nil
                content = prettifiedIfJSON(raw) ?? raw
            }
        } catch {
            content = "Error loading file: \(error.localizedDescription)"
            chatSessionPreview = nil
        }
    }
    
    private func saveFile() {
        do {
            try content.write(to: fileItem.path, atomically: true, encoding: .utf8)
            loadFile()
        } catch {
            print("Error saving file: \(error.localizedDescription)")
        }
    }

    private func prettifiedIfJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return prettyPrintedJSONString(from: data)
    }

    private func prettyPrintedJSONString(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return pretty
    }
}
