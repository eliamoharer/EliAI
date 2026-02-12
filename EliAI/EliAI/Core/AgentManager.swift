import Foundation
import Observation

@Observable
class AgentManager {
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }
    
    func processToolCalls(in text: String) async -> String? {
        // Robust regex parser for <tool_call>...</tool_call>
        // Use s (dotMatchesLineSeparators) option in pattern string if supported, or via options
        // We use (?s) to enable dotAll mode inline
        let pattern = "(?s)<tool_call>(.*?)</tool_call>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for result in results {
            if result.numberOfRanges > 1 {
                let range = result.range(at: 1)
                let jsonString = nsString.substring(with: range)
                
                // Clean up potential markdown formatting (```json ... ```)
                let cleanJson = jsonString.replacingOccurrences(of: "```json", with: "")
                                          .replacingOccurrences(of: "```", with: "")
                                          .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let data = cleanJson.data(using: .utf8),
                   let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                    AppLogger.info("Tool call parsed: \(toolCall.name)", category: .agent)
                    return await execute(toolCall)
                }
            }
        }
        
        return nil
    }
    
    private func execute(_ toolCall: ToolCall) async -> String {
        do {
            switch toolCall.name {
            case "create_file":
                guard let path = toolCall.arguments["path"], let content = toolCall.arguments["content"] else { return "Error: Missing arguments" }
                try fileSystem.createFile(path: path, content: content)
                AppLogger.info("Tool executed: create_file path=\(path)", category: .agent)
                return "File created at \(path)"

            case "read_file":
                guard let path = toolCall.arguments["path"] else { return "Error: Missing arguments" }
                let content = try fileSystem.readFile(path: path)
                AppLogger.info("Tool executed: read_file path=\(path)", category: .agent)
                return content

            case "list_files":
                let directory = toolCall.arguments["directory"] ?? ""
                let files = try fileSystem.listFiles(directory: directory)
                AppLogger.info("Tool executed: list_files directory=\(directory)", category: .agent)
                return files.joined(separator: "\n")

            case "create_memory":
                guard let title = toolCall.arguments["title"], let content = toolCall.arguments["content"] else {
                    return "Error: Missing arguments"
                }
                let slug = safeSlug(from: title)
                let path = "memory/\(slug).md"
                try fileSystem.createFile(path: path, content: content)
                AppLogger.info("Tool executed: create_memory title=\(title)", category: .agent)
                return "Memory created: \(path)"

            case "create_task":
                guard let title = toolCall.arguments["title"] else {
                    return "Error: Missing arguments"
                }
                let due = toolCall.arguments["due"] ?? "unscheduled"
                let details = toolCall.arguments["details"] ?? ""
                let slug = safeSlug(from: title)
                let content = """
                # \(title)

                Due: \(due)

                \(details)
                """
                let path = "tasks/\(slug).md"
                try fileSystem.createFile(path: path, content: content)
                AppLogger.info("Tool executed: create_task title=\(title)", category: .agent)
                return "Task created: \(path)"

            default:
                AppLogger.warning("Unknown tool requested: \(toolCall.name)", category: .agent)
                return "Error: Unknown tool \(toolCall.name)"
            }
        } catch {
            AppLogger.error("Tool execution failed for \(toolCall.name): \(error.localizedDescription)", category: .agent)
            return "Error: \(error.localizedDescription)"
        }
    }

    private func safeSlug(from input: String) -> String {
        let cleaned = input
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}

struct ToolCall: Codable, Equatable {
    let name: String
    let arguments: [String: String]
}
