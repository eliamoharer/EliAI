import Foundation
import Observation

@Observable
class AgentManager {
    private let fileSystem: FileSystemManager
    
    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }
    
    func processToolCalls(in text: String) async -> String? {
        let payloads = extractToolCallPayloads(from: text)
        let candidates = payloads.isEmpty ? extractLooseToolCallPayloads(from: text) : payloads
        let uniquePayloads = Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
        guard !uniquePayloads.isEmpty else { return nil }

        var toolOutputs: [String] = []

        for payload in uniquePayloads {
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
    
    private func execute(_ toolCall: ToolCall) async -> String {
        do {
            switch toolCall.name {
            case "create_file":
                guard let path = requiredArgument("path", in: toolCall.arguments),
                      let content = requiredArgument("content", in: toolCall.arguments) else {
                    return "Error: Missing arguments"
                }
                try fileSystem.createFile(path: path, content: content)
                AppLogger.info("Tool executed: create_file path=\(path)", category: .agent)
                return "File created at \(path)"

            case "read_file":
                guard let path = requiredArgument("path", in: toolCall.arguments) else {
                    return "Error: Missing arguments"
                }
                let content = try fileSystem.readFile(path: path)
                AppLogger.info("Tool executed: read_file path=\(path)", category: .agent)
                return content

            case "list_files":
                let directory = toolCall.arguments["directory"] ?? ""
                let files = try fileSystem.listFiles(directory: directory)
                AppLogger.info("Tool executed: list_files directory=\(directory)", category: .agent)
                return files.joined(separator: "\n")

            case "create_memory":
                guard let title = requiredArgument("title", in: toolCall.arguments),
                      let content = requiredArgument("content", in: toolCall.arguments) else {
                    return "Error: Missing arguments"
                }
                let slug = safeSlug(from: title)
                let path = "memory/\(slug).md"
                try fileSystem.createFile(path: path, content: content)
                AppLogger.info("Tool executed: create_memory title=\(title)", category: .agent)
                return "Memory created: \(path)"

            case "create_task":
                guard let title = requiredArgument("title", in: toolCall.arguments) else {
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

    private func extractToolCallPayloads(from text: String) -> [String] {
        let pattern = "(?s)<tool_call>(.*?)</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { result in
            guard result.numberOfRanges > 1 else { return nil }
            return nsString.substring(with: result.range(at: 1))
        }
    }

    private func extractLooseToolCallPayloads(from text: String) -> [String] {
        // Fallback for models that emit raw/fenced JSON without <tool_call> wrappers.
        let pattern = #"(?s)```(?:json)?\s*(\{.*?"name"\s*:\s*"(?:create_file|read_file|list_files|create_memory|create_task)".*?"arguments"\s*:\s*\{.*?\}\s*\})\s*```|\{[^{}]*"name"\s*:\s*"(?:create_file|read_file|list_files|create_memory|create_task)"[^{}]*"arguments"\s*:\s*\{.*?\}\s*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

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

        for candidate in jsonCandidates(from: cleaned) {
            guard let data = candidate.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else {
                continue
            }

            let argumentsAny = json["arguments"] as? [String: Any] ?? [:]
            var arguments: [String: String] = [:]
            for (key, value) in argumentsAny {
                arguments[key] = stringifyJSONValue(value)
            }

            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedName.isEmpty {
                continue
            }
            return ToolCall(name: normalizedName, arguments: arguments)
        }

        return nil
    }

    private func jsonCandidates(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedBackslashes = sanitizeJSONString(trimmed)
        let withoutTrailingCommas = sanitizedBackslashes.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )

        var candidates: [String] = []
        for candidate in [trimmed, sanitizedBackslashes, withoutTrailingCommas] {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty && !candidates.contains(normalized) {
                candidates.append(normalized)
            }
        }
        return candidates
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

    private func stringifyJSONValue(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if value is NSNull {
            return ""
        }
        if let number = value as? NSNumber {
            let typeCode = String(cString: number.objCType)
            if typeCode == "c" {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let dictionary = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: []),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func sanitizeJSONString(_ jsonString: String) -> String {
        if (try? JSONSerialization.jsonObject(with: Data(jsonString.utf8))) != nil {
            return jsonString
        }

        var result = ""
        var inString = false
        var escapeNext = false
        var index = jsonString.startIndex

        while index < jsonString.endIndex {
            let char = jsonString[index]

            if escapeNext {
                if inString {
                    let validEscapes = "\"\\/bfnrtu"
                    if validEscapes.contains(char) {
                        result.append("\\")
                        result.append(char)
                    } else {
                        result.append("\\\\")
                        result.append(char)
                    }
                } else {
                    result.append("\\")
                    result.append(char)
                }
                escapeNext = false
            } else if char == "\\" {
                if inString {
                    let nextIndex = jsonString.index(after: index)
                    if nextIndex < jsonString.endIndex {
                        let nextChar = jsonString[nextIndex]
                        let validEscapes = "\"\\/bfnrtu"
                        if validEscapes.contains(nextChar) {
                            result.append(char)
                            escapeNext = true
                        } else {
                            result.append("\\\\")
                        }
                    } else {
                        result.append("\\\\")
                    }
                } else {
                    result.append(char)
                    escapeNext = true
                }
            } else {
                if char == "\"" {
                    inString.toggle()
                }
                result.append(char)
            }

            index = jsonString.index(after: index)
        }

        return result
    }

    private func requiredArgument(_ name: String, in arguments: [String: String]) -> String? {
        guard let value = arguments[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
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
