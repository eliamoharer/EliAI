import Foundation
import Observation

private let toolCallPayloadsRegex = try! NSRegularExpression(pattern: "(?s)<tool_call>(.*?)</tool_call>", options: [])

enum ToolError: Error, LocalizedError {
    case missingArgument(String)
    case invalidArgument(String, expected: String)
    case unauthorized(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingArgument(let arg):
            return "Error: missing required argument '\(arg)'."
        case .invalidArgument(let arg, let expected):
            return "Error: invalid argument '\(arg)'. Expected \(expected)."
        case .unauthorized(let msg):
            return "Error: Unauthorized. \(msg)"
        case .executionFailed(let msg):
            return "Error: \(msg)"
        }
    }
}

@Observable
class AgentManager {
    private let fileSystem: FileSystemManager
    private let taskManager: TaskManager
    let phoneModeManager: PhoneModeManager
    
    private(set) var tools: [String: Tool] = [:]
    private var looseToolCallPayloadsRegex: NSRegularExpression?

    init(fileSystem: FileSystemManager, taskManager: TaskManager, phoneModeManager: PhoneModeManager) {
        self.fileSystem = fileSystem
        self.taskManager = taskManager
        self.phoneModeManager = phoneModeManager
        
        registerTools()
    }
    
    private func registerTools() {
        let allTools: [Tool] = [
            CreateFileTool(fileSystem: fileSystem),
            ReadFileTool(fileSystem: fileSystem),
            ListFilesTool(fileSystem: fileSystem),
            CreateMemoryTool(fileSystem: fileSystem),
            RecallMemoryTool(fileSystem: fileSystem),
            ListMemoriesTool(fileSystem: fileSystem),
            SearchMemoryTool(fileSystem: fileSystem),
            CreateTaskTool(taskManager: taskManager),
            ListTasksTool(taskManager: taskManager),
            CompleteTaskTool(taskManager: taskManager),
            CreateReminderTool(phoneModeManager: phoneModeManager),
            ListReminderListsTool(phoneModeManager: phoneModeManager),
            CreateEventTool(phoneModeManager: phoneModeManager),
            ListEventsTool(phoneModeManager: phoneModeManager),
            OpenUrlTool(phoneModeManager: phoneModeManager),
            OpenMapsTool(phoneModeManager: phoneModeManager),
            OpenMapsDirectionsTool(phoneModeManager: phoneModeManager),
            RunShortcutTool(phoneModeManager: phoneModeManager),
            SaveShortcutsTool(phoneModeManager: phoneModeManager),
            LogWaterTool(phoneModeManager: phoneModeManager),
            LogSleepTool(phoneModeManager: phoneModeManager),
            LogCaffeineTool(phoneModeManager: phoneModeManager),
            LogStepsTool(phoneModeManager: phoneModeManager)
        ]
        
        for tool in allTools {
            tools[tool.name] = tool
        }
        
        let toolNames = tools.keys.joined(separator: "|")
        let pattern = #"(?s)```(?:json)?\s*(\{.*?"name"\s*:\s*"(?:"# + toolNames + #")".*?"arguments"\s*:\s*\{.*?\}\s*\})\s*```|\{[^{}]*"name"\s*:\s*"(?:"# + toolNames + #")"[^{}]*"arguments"\s*:\s*\{.*?\}\s*\}"#
        looseToolCallPayloadsRegex = try? NSRegularExpression(pattern: pattern, options: [])
    }
    
    var toolPromptString: String {
        return tools.values
            .sorted { $0.name < $1.name }
            .map { "- \($0.signatureString): \($0.description)" }
            .joined(separator: "\n")
    }

    func processToolCalls(in text: String) async -> String? {
        let strictPayloads = uniqueStrings(in: extractToolCallPayloads(from: text))
        if !strictPayloads.isEmpty {
            var toolOutputs: [String] = []
            for payload in strictPayloads {
                guard let toolCall = parseToolCall(from: payload) else {
                    AppLogger.warning("Failed to parse tool_call payload.", category: .agent)
                    toolOutputs.append("<tool_result>\nError: Invalid tool_call payload. Use valid JSON with string arguments.\n</tool_result>")
                    continue
                }

                AppLogger.info("Tool call parsed: \(toolCall.name)", category: .agent)
                let output = await execute(toolCall)
                toolOutputs.append("<tool_result>\n\(output)\n</tool_result>")
            }
            return toolOutputs.isEmpty ? nil : toolOutputs.joined(separator: "\n\n")
        }

        let loosePayloads = uniqueStrings(in: extractLooseToolCallPayloads(from: text))
        if !loosePayloads.isEmpty {
            var toolOutputs: [String] = []
            for payload in loosePayloads {
                guard let toolCall = parseToolCall(from: payload) else { continue }
                AppLogger.info("Loose tool call parsed: \(toolCall.name)", category: .agent)
                let output = await execute(toolCall)
                toolOutputs.append("<tool_result>\n\(output)\n</tool_result>")
            }
            if !toolOutputs.isEmpty {
                return toolOutputs.joined(separator: "\n\n")
            }
        }

        return nil
    }

    // MARK: - Tool Execution

    private func execute(_ toolCall: ToolCall) async -> String {
        guard let tool = tools[toolCall.name] else {
            AppLogger.warning("Unknown tool requested: \(toolCall.name)", category: .agent)
            return "Error: Unknown tool '\(toolCall.name)'."
        }
        
        do {
            return try await tool.execute(arguments: toolCall.arguments)
        } catch let error as ToolError {
            return error.localizedDescription
        } catch {
            AppLogger.error("Tool execution failed for \(toolCall.name): \(error.localizedDescription)", category: .agent)
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Tool Call Extraction

    private func extractToolCallPayloads(from text: String) -> [String] {
        let nsString = text as NSString
        let matches = toolCallPayloadsRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { result in
            guard result.numberOfRanges > 1 else { return nil }
            return nsString.substring(with: result.range(at: 1))
        }
    }

    private func extractLooseToolCallPayloads(from text: String) -> [String] {
        guard let regex = looseToolCallPayloadsRegex else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                return nsText.substring(with: match.range(at: 1))
            }
            guard match.range.location != NSNotFound else { return nil }
            return nsText.substring(with: match.range)
        }
    }

    private func parseToolCall(from rawPayload: String) -> ToolCall? {
        let cleaned = stripCodeFences(rawPayload).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Find the first '{' and last '}' to extract valid JSON even if it's surrounded by junk
        guard let firstBrace = cleaned.firstIndex(of: "{"),
              let lastBrace = cleaned.lastIndex(of: "}") else {
            return nil
        }
        
        let jsonString = String(cleaned[firstBrace...lastBrace])
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return nil
        }

        let argumentsAny = (json["arguments"] as? [String: Any])
            ?? (json["args"] as? [String: Any])
            ?? [:]
        var arguments: [String: String] = [:]
        for (key, value) in argumentsAny {
            arguments[key] = String(describing: value)
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        return ToolCall(name: normalizedName, arguments: arguments)
    }
    
    private func stripCodeFences(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"^```(?:json)?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"\s*```$"#,
            with: "",
            options: .regularExpression
        )
        return value
    }

    private func uniqueStrings(in values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            ordered.append(value)
        }
        return ordered
    }
}

struct ToolCall: Codable, Equatable {
    let name: String
    let arguments: [String: String]
}
