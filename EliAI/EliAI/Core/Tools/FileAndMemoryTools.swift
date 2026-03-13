import Foundation

struct CreateFileTool: Tool {
    let name = "create_file"
    let description = "Create a new file"
    let parameters = ["path", "content"]
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let path = arguments["path"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { throw ToolError.missingArgument("path") }
        guard let content = arguments["content"]?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { throw ToolError.missingArgument("content") }
        
        try fileSystem.createFile(path: path, content: content)
        AppLogger.info("Tool executed: create_file path=\(path)", category: .agent)
        return "File created at \(path)"
    }
}

struct ReadFileTool: Tool {
    let name = "read_file"
    let description = "Read a file's content"
    let parameters = ["path"]
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let path = arguments["path"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { throw ToolError.missingArgument("path") }
        
        let content = try fileSystem.readFile(path: path)
        AppLogger.info("Tool executed: read_file path=\(path)", category: .agent)
        return content
    }
}

struct ListFilesTool: Tool {
    let name = "list_files"
    let description = "List files in a directory"
    let parameters = ["directory"]
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        let directory = arguments["directory"]
            ?? arguments["path"]
            ?? arguments["folder"]
            ?? arguments["dir"]
            ?? ""
            
        let files = try fileSystem.listFiles(directory: directory)
        AppLogger.info("Tool executed: list_files directory=\(directory)", category: .agent)
        return files.isEmpty ? "(empty directory)" : files.joined(separator: "\n")
    }
}

struct CreateMemoryTool: Tool {
    let name = "create_memory"
    let description = "Create a memory note"
    let parameters = ["title", "content"]
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        guard let content = arguments["content"]?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { throw ToolError.missingArgument("content") }
        
        let slug = title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let finalSlug = slug.isEmpty ? UUID().uuidString : slug
        
        let header = "# \(title)\n\n"
        let path = "memory/\(finalSlug).md"
        try fileSystem.createFile(path: path, content: header + content)
        AppLogger.info("Tool executed: create_memory title=\(title)", category: .agent)
        return "Memory saved: \(title)"
    }
}

struct RecallMemoryTool: Tool {
    let name = "recall_memory"
    let description = "Recall a memory by title"
    let parameters = ["title?"]
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            let files = try fileSystem.listFiles(directory: "memory")
            let mdFiles = files.filter { $0.hasSuffix(".md") }
            guard !mdFiles.isEmpty else { return "No memories stored yet." }
            var result = "Memories:\n"
            for file in mdFiles {
                let content = try fileSystem.readFile(path: "memory/\(file)")
                let preview = String(content.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                result += "- \(file): \(preview)\n"
            }
            AppLogger.info("Tool executed: recall_memory (all)", category: .agent)
            return result
        } else {
            let slug = title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let candidates = [
                "memory/\(slug).md",
                "memory/\(title).md",
                "memory/\(title.lowercased()).md"
            ]
            for candidate in candidates {
                if let content = try? fileSystem.readFile(path: candidate) {
                    AppLogger.info("Tool executed: recall_memory title=\(title)", category: .agent)
                    return content
                }
            }
            // Fallback to searching
            return SearchMemoryTool(fileSystem: fileSystem).searchMemoryFiles(query: title)
        }
    }
}

struct ListMemoriesTool: Tool {
    let name = "list_memories"
    let description = "List all memories"
    let parameters = []
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        let files = try fileSystem.listFiles(directory: "memory")
        let mdFiles = files.filter { $0.hasSuffix(".md") }
        guard !mdFiles.isEmpty else { return "No memories stored yet." }
        AppLogger.info("Tool executed: list_memories", category: .agent)
        return mdFiles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}

struct SearchMemoryTool: Tool {
    let name = "search_memory"
    let description = "Search memories for a query"
    let parameters = ["query"]
    let fileSystem: FileSystemManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let query = arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { throw ToolError.missingArgument("query") }
        AppLogger.info("Tool executed: search_memory query=\(query)", category: .agent)
        return searchMemoryFiles(query: query)
    }
    
    func searchMemoryFiles(query: String) -> String {
        let lowerQuery = query.lowercased()
        guard let files = try? fileSystem.listFiles(directory: "memory") else {
            return "No memories found."
        }

        var results: [(file: String, snippet: String)] = []
        for file in files where file.hasSuffix(".md") {
            guard let content = try? fileSystem.readFile(path: "memory/\(file)") else { continue }
            if content.lowercased().contains(lowerQuery) || file.lowercased().contains(lowerQuery) {
                let preview = extractSnippet(from: content, around: lowerQuery, maxLength: 200)
                results.append((file, preview))
            }
        }

        guard !results.isEmpty else {
            return "No memories matching \"\(query)\"."
        }

        return results.map { "[\($0.file)]: \($0.snippet)" }.joined(separator: "\n\n")
    }
    
    private func extractSnippet(from text: String, around query: String, maxLength: Int) -> String {
        let lower = text.lowercased()
        guard let range = lower.range(of: query) else {
            return String(text.prefix(maxLength))
        }

        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - maxLength / 2)
        let start = text.index(text.startIndex, offsetBy: contextStart)
        let endOffset = min(text.count, contextStart + maxLength)
        let end = text.index(text.startIndex, offsetBy: endOffset)

        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if contextStart > 0 { snippet = "..." + snippet }
        if endOffset < text.count { snippet += "..." }
        return snippet
    }
}
