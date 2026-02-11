import Foundation

// MARK: - File System Manager
// Manages the app's sandboxed document directory for files, memories, tasks, and chats

@Observable
class FileSystemManager {
    let documentsURL: URL
    var rootItems: [FileItem] = []

    // Standard directories
    let memoryDir = "memory"
    let tasksDir = "tasks"
    let notesDir = "notes"
    let chatsDir = "chats"
    let modelsDir = "models"

    init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        ensureDirectoryStructure()
        refreshFileTree()
    }

    // MARK: - Directory Structure

    private func ensureDirectoryStructure() {
        let dirs = [memoryDir, tasksDir, notesDir, chatsDir, modelsDir]
        for dir in dirs {
            let url = documentsURL.appendingPathComponent(dir)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - File Tree

    func refreshFileTree() {
        rootItems = listDirectory(at: documentsURL)
            .filter { $0.name != modelsDir } // Hide models dir from explorer
    }

    func listDirectory(at url: URL) -> [FileItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { itemURL in
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let fileSize = resourceValues?.fileSize.map { Int64($0) }
            let modDate = resourceValues?.contentModificationDate

            var children: [FileItem]? = nil
            if isDirectory {
                children = listDirectory(at: itemURL)
            }

            return FileItem(
                name: itemURL.lastPathComponent,
                path: itemURL,
                isDirectory: isDirectory,
                children: children,
                fileSize: fileSize,
                modifiedDate: modDate
            )
        }.sorted { a, b in
            // Directories first, then alphabetical
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - CRUD Operations

    func createFile(relativePath: String, content: String) throws -> String {
        let sanitized = sanitizePath(relativePath)
        let url = documentsURL.appendingPathComponent(sanitized)

        // Create parent directories if needed
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        refreshFileTree()
        return "Created file: \(sanitized)"
    }

    func readFile(relativePath: String) throws -> String {
        let sanitized = sanitizePath(relativePath)
        let url = documentsURL.appendingPathComponent(sanitized)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSystemError.fileNotFound(sanitized)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    func editFile(relativePath: String, content: String) throws -> String {
        let sanitized = sanitizePath(relativePath)
        let url = documentsURL.appendingPathComponent(sanitized)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSystemError.fileNotFound(sanitized)
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        refreshFileTree()
        return "Updated file: \(sanitized)"
    }

    func deleteFile(relativePath: String) throws -> String {
        let sanitized = sanitizePath(relativePath)
        let url = documentsURL.appendingPathComponent(sanitized)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSystemError.fileNotFound(sanitized)
        }

        try FileManager.default.removeItem(at: url)
        refreshFileTree()
        return "Deleted: \(sanitized)"
    }

    func listFiles(directory: String) throws -> String {
        let sanitized = directory == "." ? "" : sanitizePath(directory)
        let url = sanitized.isEmpty ? documentsURL : documentsURL.appendingPathComponent(sanitized)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSystemError.directoryNotFound(sanitized)
        }

        let items = listDirectory(at: url)
        if items.isEmpty {
            return "Directory '\(sanitized.isEmpty ? "root" : sanitized)' is empty."
        }

        var result = "Contents of '\(sanitized.isEmpty ? "root" : sanitized)':\n"
        for item in items {
            let typeIndicator = item.isDirectory ? "📁" : "📄"
            let sizeStr = item.formattedSize.isEmpty ? "" : " (\(item.formattedSize))"
            result += "  \(typeIndicator) \(item.name)\(sizeStr)\n"
        }
        return result
    }

    func searchFiles(query: String) throws -> String {
        var results: [(path: String, line: String)] = []
        searchRecursive(in: documentsURL, query: query.lowercased(), results: &results)

        if results.isEmpty {
            return "No matches found for '\(query)'."
        }

        var output = "Search results for '\(query)':\n"
        for (path, line) in results.prefix(20) {
            let relative = path.replacingOccurrences(of: documentsURL.path + "/", with: "")
            output += "  📄 \(relative): \(line.trimmingCharacters(in: .whitespaces))\n"
        }
        if results.count > 20 {
            output += "  ... and \(results.count - 20) more matches\n"
        }
        return output
    }

    // MARK: - Search Helper

    private func searchRecursive(
        in directory: URL,
        query: String,
        results: inout [(path: String, line: String)]
    ) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }

        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                searchRecursive(in: item, query: query, results: &results)
            } else if item.pathExtension == "md" || item.pathExtension == "txt" {
                if let content = try? String(contentsOf: item, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines)
                    for line in lines {
                        if line.lowercased().contains(query) {
                            results.append((path: item.path, line: String(line.prefix(100))))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Model Directory

    var modelsDirectory: URL {
        documentsURL.appendingPathComponent(modelsDir)
    }

    func modelExists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(fileName).path)
    }

    func modelPath(fileName: String) -> URL {
        modelsDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Path Security

    private func sanitizePath(_ path: String) -> String {
        // Prevent directory traversal
        var sanitized = path
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "//", with: "/")

        // Remove leading slash
        while sanitized.hasPrefix("/") {
            sanitized = String(sanitized.dropFirst())
        }

        return sanitized
    }
}

// MARK: - Errors

enum FileSystemError: LocalizedError {
    case fileNotFound(String)
    case directoryNotFound(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .directoryNotFound(let path): return "Directory not found: \(path)"
        case .writeFailed(let msg): return "Write failed: \(msg)"
        }
    }
}
