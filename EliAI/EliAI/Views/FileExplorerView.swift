import SwiftUI

struct FileExplorerView: View {
    var fileSystem: FileSystemManager
    var chatManager: ChatManager
    var modelDownloader: ModelDownloader // Added
    var isOpaque: Bool
    var onSelectFile: (FileItem) -> Void
    
    @Binding var showingSettings: Bool
    @Binding var showingNewChatDialog: Bool
    @State private var selectedFile: FileItem?
    @State private var items: [FileItem] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Actions")) {
                    Button(action: { showingNewChatDialog = true }) {
                        Label("New Chat", systemImage: "plus.message")
                    }
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
                
                Section(header: Text("Files")) {
                    RecursiveFileView(items: items) { item in
                        selectedFile = item
                        onSelectFile(item)
                    }
                }
            }
            .navigationTitle("Brain")
            .listStyle(SidebarListStyle())
            .opacity(isOpaque ? 1.0 : 0.85)
            .onAppear {
                items = fileSystem.getAllFilesRecursive()
            }
            .navigationDestination(item: $selectedFile) { file in
                FileDetailView(fileItem: file)
            }
        }
    }
    
    // Helper view for recursion
    struct RecursiveFileView: View {
        let items: [FileItem]
        let onSelect: (FileItem) -> Void
        
        var body: some View {
            ForEach(items, id: \.self) { item in
                if item.isDirectory {
                    DisclosureGroup(
                        content: {
                            if let children = item.children {
                                RecursiveFileView(items: children, onSelect: onSelect)
                            }
                        },
                        label: {
                            Label(item.name, systemImage: "folder")
                        }
                    )
                } else {
                    Button(action: { onSelect(item) }) {
                        Label(item.name, systemImage: "doc")
                    }
                }
            }
        }
    }
}
