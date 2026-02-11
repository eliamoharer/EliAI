import Foundation

@Observable
class FileSystemManager {
    let documentsURL: URL
    
    init() {
        self.documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        createDefaultDirectories()
    }
    
    private func createDefaultDirectories() {
        let dirs = ["memory", "tasks", "chats", "notes"]
        for dir in dirs {
            let dirURL = documentsURL.appendingPathComponent(dir)
            if !FileManager.default.fileExists(atPath: dirURL.path) {
                try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - CRUD
    
    func createFile(path: String, content: String) throws {
        let fileURL = documentsURL.appendingPathComponent(path)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func readFile(path: String) throws -> String {
        let fileURL = documentsURL.appendingPathComponent(path)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
    
    func listFiles(directory: String = "") throws -> [String] {
        let dirURL = directory.isEmpty ? documentsURL : documentsURL.appendingPathComponent(directory)
        let contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
        return contents
    }
    
    func deleteFile(path: String) throws {
        let fileURL = documentsURL.appendingPathComponent(path)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Helper
    
    func getAllFilesRecursive() -> [FileItem] {
        // Implementation for the FileExplorerView tree structure
        // Returns a hierarchy of FileItem objects
        return scanDirectory(at: documentsURL)
    }
    
    private func scanDirectory(at url: URL) -> [FileItem] {
        var items: [FileItem] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let name = item.lastPathComponent
            
            if isDirectory {
                let children = scanDirectory(at: item)
                items.append(FileItem(name: name, isDirectory: true, children: children, path: item))
            } else {
                if name.hasSuffix(".md") || name.hasSuffix(".txt") || name.hasSuffix(".json") {
                     items.append(FileItem(name: name, isDirectory: false, children: nil, path: item))
                }
            }
        }
        
        return items.sorted { $0.name < $1.name }
    }
}
