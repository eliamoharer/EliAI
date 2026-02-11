import Foundation

// MARK: - Agent Tool Definition

enum AgentToolName: String, CaseIterable, Codable {
    case createFile = "create_file"
    case readFile = "read_file"
    case editFile = "edit_file"
    case deleteFile = "delete_file"
    case listFiles = "list_files"
    case createMemory = "create_memory"
    case createTask = "create_task"
    case searchFiles = "search_files"

    var description: String {
        switch self {
        case .createFile: return "Create a new file with the given content"
        case .readFile: return "Read the contents of a file"
        case .editFile: return "Replace the contents of an existing file"
        case .deleteFile: return "Delete a file"
        case .listFiles: return "List all files in a directory"
        case .createMemory: return "Save an important memory or note"
        case .createTask: return "Create a task or reminder"
        case .searchFiles: return "Search across all files for a query"
        }
    }

    var requiredParams: [String] {
        switch self {
        case .createFile: return ["path", "content"]
        case .readFile: return ["path"]
        case .editFile: return ["path", "content"]
        case .deleteFile: return ["path"]
        case .listFiles: return ["directory"]
        case .createMemory: return ["title", "content"]
        case .createTask: return ["title"]
        case .searchFiles: return ["query"]
        }
    }

    var optionalParams: [String] {
        switch self {
        case .createTask: return ["due", "details"]
        default: return []
        }
    }
}

// MARK: - Tool Call Parser

struct ToolCallParser {
    /// Parses tool calls from LLM output.
    /// Format: <tool>tool_name|param1=value1|param2=value2</tool>
    static func parse(from text: String) -> [ToolCall] {
        var calls: [ToolCall] = []
        let pattern = #"<tool>(.*?)</tool>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return calls
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            if let range = Range(match.range(at: 1), in: text) {
                let inner = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let toolCall = parseToolCall(inner) {
                    calls.append(toolCall)
                }
            }
        }

        return calls
    }

    /// Check if text contains a partial (unclosed) tool call — indicates model is still generating
    static func containsPartialToolCall(in text: String) -> Bool {
        let openCount = text.components(separatedBy: "<tool>").count - 1
        let closeCount = text.components(separatedBy: "</tool>").count - 1
        return openCount > closeCount
    }

    /// Strips tool call XML from display text
    static func stripToolCalls(from text: String) -> String {
        let pattern = #"<tool>.*?</tool>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return text
        }
        let nsText = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseToolCall(_ raw: String) -> ToolCall? {
        let parts = raw.components(separatedBy: "|")
        guard let toolNameStr = parts.first?.trimmingCharacters(in: .whitespaces),
              let toolName = AgentToolName(rawValue: toolNameStr) else {
            return nil
        }

        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces)
                let value = kv.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                params[key] = value
            }
        }

        // Validate required params
        for required in toolName.requiredParams {
            if params[required] == nil {
                return nil
            }
        }

        return ToolCall(toolName: toolName.rawValue, parameters: params)
    }
}

// MARK: - System Prompt

struct AgentSystemPrompt {
    static let prompt: String = """
    You are EliAI, a helpful personal AI assistant running entirely on the user's device. Everything is private and local.

    You can manage files, create memories, and set tasks using tools. When you need to perform an action, use this exact format:

    <tool>tool_name|param1=value1|param2=value2</tool>

    Available tools:
    - create_file|path=...|content=... — Create a new file
    - read_file|path=... — Read a file's contents
    - edit_file|path=...|content=... — Replace a file's contents
    - delete_file|path=... — Delete a file
    - list_files|directory=... — List files in a directory (use "." for root)
    - create_memory|title=...|content=... — Save an important memory in memory/
    - create_task|title=...|due=...|details=... — Create a task in tasks/ (due and details are optional)
    - search_files|query=... — Search across all files

    After a tool executes, you'll see the result in a <result>...</result> block. Use it to continue helping the user.

    Guidelines:
    - Be concise and helpful
    - Proactively save important information as memories
    - When the user asks you to remember something, use create_memory
    - When the user mentions a task or to-do, offer to create_task
    - Use markdown formatting in files you create
    - File paths are relative to the app's document directory
    - Always confirm actions you've taken
    """
}
