import Foundation

// MARK: - Agent Manager
// Orchestrates tool execution based on LLM output, managing the agentic loop

@Observable
class AgentManager {
    let fileSystem: FileSystemManager
    var lastToolResult: String?
    var executingTool: String?

    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }

    // MARK: - Process LLM Output

    /// Processes a complete LLM response, executing any tool calls found.
    /// Returns (display text, tool results to feed back to LLM, whether tools were called)
    func processResponse(_ response: String) async -> (displayText: String, toolFeedback: String?, hasToolCalls: Bool) {
        let toolCalls = ToolCallParser.parse(from: response)
        let displayText = ToolCallParser.stripToolCalls(from: response)

        guard !toolCalls.isEmpty else {
            return (displayText, nil, false)
        }

        var feedback = ""
        for call in toolCalls {
            await MainActor.run {
                self.executingTool = call.toolName
            }

            let result = await executeTool(call)

            feedback += "<result>\n\(result)\n</result>\n"

            await MainActor.run {
                self.lastToolResult = result
            }
        }

        await MainActor.run {
            self.executingTool = nil
        }

        return (displayText, feedback, true)
    }

    // MARK: - Tool Execution

    func executeTool(_ call: ToolCall) async -> String {
        guard let toolName = AgentToolName(rawValue: call.toolName) else {
            return "Error: Unknown tool '\(call.toolName)'"
        }

        do {
            switch toolName {
            case .createFile:
                let path = call.parameters["path"]!
                let content = call.parameters["content"]!
                return try fileSystem.createFile(relativePath: path, content: content)

            case .readFile:
                let path = call.parameters["path"]!
                let content = try fileSystem.readFile(relativePath: path)
                return "Contents of \(path):\n\(content)"

            case .editFile:
                let path = call.parameters["path"]!
                let content = call.parameters["content"]!
                return try fileSystem.editFile(relativePath: path, content: content)

            case .deleteFile:
                let path = call.parameters["path"]!
                return try fileSystem.deleteFile(relativePath: path)

            case .listFiles:
                let dir = call.parameters["directory"]!
                return try fileSystem.listFiles(directory: dir)

            case .createMemory:
                let title = call.parameters["title"]!
                let content = call.parameters["content"]!
                return try createMemory(title: title, content: content)

            case .createTask:
                let title = call.parameters["title"]!
                let due = call.parameters["due"]
                let details = call.parameters["details"]
                return try createTask(title: title, due: due, details: details)

            case .searchFiles:
                let query = call.parameters["query"]!
                return try fileSystem.searchFiles(query: query)
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Memory & Tasks

    private func createMemory(title: String, content: String) throws -> String {
        let sanitizedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        let fileName = "memory/\(sanitizedTitle).md"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: Date())

        let fileContent = """
        # \(title)

        *Created: \(dateStr)*

        \(content)
        """

        return try fileSystem.createFile(relativePath: fileName, content: fileContent)
    }

    private func createTask(title: String, due: String?, details: String?) throws -> String {
        let sanitizedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        let fileName = "tasks/\(sanitizedTitle).md"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: Date())

        var fileContent = "# \(title)\n\n"
        fileContent += "*Created: \(dateStr)*\n"

        if let due = due, !due.isEmpty {
            fileContent += "*Due: \(due)*\n"
        }

        fileContent += "\n- [ ] \(title)\n"

        if let details = details, !details.isEmpty {
            fileContent += "\n## Details\n\n\(details)\n"
        }

        return try fileSystem.createFile(relativePath: fileName, content: fileContent)
    }
}
