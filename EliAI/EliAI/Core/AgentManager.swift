import Foundation

@Observable
class AgentManager {
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }
    
    func processToolCalls(in text: String) async -> String? {
        // Simple regex parser for <tool_call>...</tool_call>
        // In a real implementation, you'd use a more robust parser or structured output mode from llama.cpp
        
        // Example format: <tool_call>{"name": "create_file", "arguments": {"path": "notes/idea.md", "content": "hello"}}</tool_call>
        
        guard let regex = try? Regex(/<tool_call>(.*?)<\/tool_call>/) else { return nil }
        
        if let match = text.firstMatch(of: regex) {
            let jsonString = String(match.output.1)
            if let data = jsonString.data(using: .utf8),
               let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                return await execute(toolCall)
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

struct ToolCall: Codable {
    let name: String
    let arguments: [String: String]
}
