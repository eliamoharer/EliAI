import Foundation

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
                    return await execute(toolCall)
                }
            }
        }
        
        return nil
    }
    
    private func execute(_ toolCall: ToolCall) async -> String {
        // Run file operations on a background thread to avoid blocking the main thread (UI)
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return "Error: Agent Manager deallocated" }
            do {
                switch toolCall.name {
                case "create_file":
                    guard let path = toolCall.arguments["path"], let content = toolCall.arguments["content"] else { return "Error: Missing arguments" }
                    try self.fileSystem.createFile(path: path, content: content)
                    return "File created at \(path)"
                    
                case "read_file":
                    guard let path = toolCall.arguments["path"] else { return "Error: Missing arguments" }
                    let content = try self.fileSystem.readFile(path: path)
                    return content
                    
                case "list_files":
                    let directory = toolCall.arguments["directory"] ?? ""
                    let files = try self.fileSystem.listFiles(directory: directory)
                    return files.joined(separator: "\n")
                    
                default:
                    return "Error: Unknown tool \(toolCall.name)"
                }
            } catch {
                return "Error: \(error.localizedDescription)"
            }
        }.value
    }
}

struct ToolCall: Codable, Equatable {
    let name: String
    let arguments: [String: String]
}
