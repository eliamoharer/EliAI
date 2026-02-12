import Foundation

@Observable
class AgentManager {
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }
    
    func processToolCalls(in text: String) async -> String? {
        // Simple regex parser for <tool_call>...</tool_call>
        let pattern = "<tool_call>(.*?)</tool_call>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for result in results {
            if result.numberOfRanges > 1 {
                let range = result.range(at: 1)
                let jsonString = nsString.substring(with: range)
                
                if let data = jsonString.data(using: .utf8),
                   let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
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
                return "File created at \(path)"
                
            case "read_file":
                guard let path = toolCall.arguments["path"] else { return "Error: Missing arguments" }
                let content = try fileSystem.readFile(path: path)
                return content
                
            case "list_files":
                let directory = toolCall.arguments["directory"] ?? ""
                let files = try fileSystem.listFiles(directory: directory)
                return files.joined(separator: "\n")
                
            default:
                return "Error: Unknown tool \(toolCall.name)"
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

struct ToolCall: Codable, Equatable {
    let name: String
    let arguments: [String: String]
}
