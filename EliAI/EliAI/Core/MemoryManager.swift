import Foundation

@Observable
class MemoryManager {
    // For now, this just interfaces with FileSystemManager to save notes in 'memory/'
    // In the future, this could use embeddings for retrieval.
    
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }
    
    func addMemory(title: String, content: String) {
        let filename = "memory/\(title.replacingOccurrences(of: " ", with: "_")).md"
        try? fileSystem.createFile(path: filename, content: content)
    }
    
    func getMemories() -> [FileItem] {
        return (try? fileSystem.listFiles(directory: "memory").map { 
            FileItem(name: $0, isDirectory: false, children: nil, path: URL(fileURLWithPath: $0)) 
        }) ?? []
    }
}
