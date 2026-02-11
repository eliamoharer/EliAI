import SwiftUI

struct FileDetailView: View {
    let fileItem: FileItem
    @State private var content: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack {
            if isEditing {
                TextEditor(text: $content)
                    .padding()
            } else {
                ScrollView {
                    Text(content)
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
            content = try String(contentsOf: fileItem.path, encoding: .utf8)
        } catch {
            content = "Error loading file: \(error.localizedDescription)"
        }
    }
    
    private func saveFile() {
        do {
            try content.write(to: fileItem.path, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving file: \(error.localizedDescription)")
        }
    }
}
