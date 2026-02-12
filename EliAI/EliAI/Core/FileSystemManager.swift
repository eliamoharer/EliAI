import Foundation
import Observation

enum FileSystemError: LocalizedError {
    case invalidPath
    case outsideSandbox

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Invalid file path."
        case .outsideSandbox:
            return "Path is outside the app sandbox."
        }
    }
}

@Observable
class FileSystemManager {
    let documentsURL: URL

    init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        createDefaultDirectories()
    }

    private func createDefaultDirectories() {
        let dirs = ["memory", "tasks", "chats", "notes"]
        for dir in dirs {
            let dirURL = documentsURL.appendingPathComponent(dir, isDirectory: true)
            if !FileManager.default.fileExists(atPath: dirURL.path) {
                try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        }
    }

    func createFile(path: String, content: String) throws {
        let fileURL = try resolveSafeURL(for: path, isDirectory: false)
        let parent = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        AppLogger.debug("Wrote file \(path)", category: .fileSystem)
    }

    func readFile(path: String) throws -> String {
        let fileURL = try resolveSafeURL(for: path, isDirectory: false)
        AppLogger.debug("Read file \(path)", category: .fileSystem)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func listFiles(directory: String = "") throws -> [String] {
        let dirURL = try resolveSafeURL(for: directory, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(atPath: dirURL.path).sorted()
    }

    func deleteFile(path: String) throws {
        let fileURL = try resolveSafeURL(for: path, isDirectory: false)
        try FileManager.default.removeItem(at: fileURL)
        AppLogger.debug("Deleted file \(path)", category: .fileSystem)
    }

    func getAllFilesRecursive() -> [FileItem] {
        scanDirectory(at: documentsURL)
    }

    private func scanDirectory(at url: URL) -> [FileItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var items: [FileItem] = []
        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let name = item.lastPathComponent

            if isDirectory {
                let children = scanDirectory(at: item)
                items.append(FileItem(name: name, isDirectory: true, children: children, path: item))
            } else if name.hasSuffix(".md") || name.hasSuffix(".txt") || name.hasSuffix(".json") || name.hasSuffix(".gguf") {
                items.append(FileItem(name: name, isDirectory: false, children: nil, path: item))
            }
        }

        return items.sorted { $0.name < $1.name }
    }

    private func resolveSafeURL(for relativePath: String, isDirectory: Bool) throws -> URL {
        if relativePath.contains("\0") {
            throw FileSystemError.invalidPath
        }

        let clean = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = clean.isEmpty
            ? documentsURL
            : documentsURL.appendingPathComponent(clean, isDirectory: isDirectory)

        let standardizedBase = documentsURL.standardizedFileURL.path
        let standardizedResolved = resolved.standardizedFileURL.path
        guard standardizedResolved.hasPrefix(standardizedBase) else {
            throw FileSystemError.outsideSandbox
        }

        return resolved
    }
}
