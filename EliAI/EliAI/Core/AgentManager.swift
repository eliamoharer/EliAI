import Foundation
import Observation

private let allToolNames: Set<String> = [
    "create_file", "read_file", "list_files",
    "create_memory", "recall_memory", "list_memories", "search_memory",
    "create_task", "list_tasks", "complete_task",
    "create_reminder", "list_reminder_lists",
    "log_water", "log_sleep", "log_caffeine", "log_steps",
    "create_event", "list_events",
    "open_url", "open_maps", "open_maps_directions",
    "run_shortcut", "save_shortcuts_to_memory"
]

private let looseToolNamePattern: String = allToolNames.joined(separator: "|")

@Observable
class AgentManager {
    private let fileSystem: FileSystemManager
    private let taskManager: TaskManager
    let phoneModeManager: PhoneModeManager

    init(fileSystem: FileSystemManager, taskManager: TaskManager, phoneModeManager: PhoneModeManager) {
        self.fileSystem = fileSystem
        self.taskManager = taskManager
        self.phoneModeManager = phoneModeManager
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
        guard !loosePayloads.isEmpty else { return nil }

        var toolOutputs: [String] = []
        for payload in loosePayloads {
            guard let toolCall = parseToolCall(from: payload) else {
                continue
            }
            AppLogger.info("Loose tool call parsed: \(toolCall.name)", category: .agent)
            let output = await execute(toolCall)
            toolOutputs.append("<tool_result>\n\(output)\n</tool_result>")
        }
        return toolOutputs.isEmpty ? nil : toolOutputs.joined(separator: "\n\n")
    }

    // MARK: - Tool Execution

    private func execute(_ toolCall: ToolCall) async -> String {
        do {
            switch toolCall.name {

            // ── File tools ──────────────────────────────────────────────

            case "create_file":
                guard let path = requiredArgument("path", in: toolCall.arguments),
                      let content = requiredArgument("content", in: toolCall.arguments) else {
                    return "Error: create_file requires 'path' and 'content'."
                }
                try fileSystem.createFile(path: path, content: content)
                AppLogger.info("Tool executed: create_file path=\(path)", category: .agent)
                return "File created at \(path)"

            case "read_file":
                guard let path = requiredArgument("path", in: toolCall.arguments) else {
                    return "Error: read_file requires 'path'."
                }
                let content = try fileSystem.readFile(path: path)
                AppLogger.info("Tool executed: read_file path=\(path)", category: .agent)
                return content

            case "list_files":
                let directory = toolCall.arguments["directory"]
                    ?? toolCall.arguments["path"]
                    ?? toolCall.arguments["folder"]
                    ?? toolCall.arguments["dir"]
                    ?? ""
                let files = try fileSystem.listFiles(directory: directory)
                AppLogger.info("Tool executed: list_files directory=\(directory)", category: .agent)
                return files.isEmpty ? "(empty directory)" : files.joined(separator: "\n")

            // ── Memory tools ────────────────────────────────────────────

            case "create_memory":
                guard let title = requiredArgument("title", in: toolCall.arguments),
                      let content = requiredArgument("content", in: toolCall.arguments) else {
                    return "Error: create_memory requires 'title' and 'content'."
                }
                let slug = safeSlug(from: title)
                let header = "# \(title)\n\n"
                let path = "memory/\(slug).md"
                try fileSystem.createFile(path: path, content: header + content)
                AppLogger.info("Tool executed: create_memory title=\(title)", category: .agent)
                return "Memory saved: \(title)"

            case "recall_memory":
                let title = toolCall.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
                    let slug = safeSlug(from: title)
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
                    return searchMemoryFiles(query: title)
                }

            case "list_memories":
                let files = try fileSystem.listFiles(directory: "memory")
                let mdFiles = files.filter { $0.hasSuffix(".md") }
                guard !mdFiles.isEmpty else { return "No memories stored yet." }
                AppLogger.info("Tool executed: list_memories", category: .agent)
                return mdFiles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

            case "search_memory":
                guard let query = requiredArgument("query", in: toolCall.arguments) else {
                    return "Error: search_memory requires 'query'."
                }
                AppLogger.info("Tool executed: search_memory query=\(query)", category: .agent)
                return searchMemoryFiles(query: query)

            // ── Task tools ──────────────────────────────────────────────

            case "create_task":
                guard let title = requiredArgument("title", in: toolCall.arguments) else {
                    return "Error: create_task requires 'title'."
                }
                let details = toolCall.arguments["details"] ?? ""
                let dueDate = parseDueDate(from: toolCall.arguments["due"])
                let task = taskManager.addTask(title: title, details: details, dueDate: dueDate)
                let dueStr = task.dueDate.map { " (due: \(formattedDate($0)))" } ?? ""
                AppLogger.info("Tool executed: create_task title=\(title)", category: .agent)
                return "Task created: \(title)\(dueStr)"

            case "list_tasks":
                let includeCompleted = toolCall.arguments["include_completed"]?.lowercased() == "true"
                AppLogger.info("Tool executed: list_tasks", category: .agent)
                return taskManager.listTasks(includeCompleted: includeCompleted)

            case "complete_task":
                guard let title = requiredArgument("title", in: toolCall.arguments) else {
                    return "Error: complete_task requires 'title'."
                }
                AppLogger.info("Tool executed: complete_task title=\(title)", category: .agent)
                return taskManager.completeTask(matching: title)

            // ── Reminders (EventKit) ─────────────────────────────────────

            case "create_reminder":
                guard let title = requiredArgument("title", in: toolCall.arguments) else {
                    return "Error: create_reminder requires 'title'."
                }
                return await phoneModeManager.createReminder(
                    title: title,
                    notes: toolCall.arguments["notes"],
                    dueDateString: toolCall.arguments["due_date"],
                    list: toolCall.arguments["list"]
                )

            case "list_reminder_lists":
                return await phoneModeManager.listReminderLists()

            // ── Health (HealthKit) ───────────────────────────────────────

            case "log_water":
                guard let amountStr = requiredArgument("amount_ml", in: toolCall.arguments),
                      let amount = Double(amountStr) else {
                    return "Error: log_water requires 'amount_ml' (number)."
                }
                return await phoneModeManager.logWater(amountML: amount)

            case "log_sleep":
                guard let start = requiredArgument("start_time", in: toolCall.arguments),
                      let end = requiredArgument("end_time", in: toolCall.arguments) else {
                    return "Error: log_sleep requires 'start_time' and 'end_time'."
                }
                return await phoneModeManager.logSleep(startTime: start, endTime: end, quality: toolCall.arguments["quality"])

            case "log_caffeine":
                let amountStr = toolCall.arguments["amount_mg"] ?? "95"
                let amount = Double(amountStr) ?? 95
                return await phoneModeManager.logCaffeine(amountMG: amount)

            case "log_steps":
                guard let countStr = requiredArgument("count", in: toolCall.arguments),
                      let count = Int(countStr) else {
                    return "Error: log_steps requires 'count' (integer)."
                }
                return await phoneModeManager.logSteps(count: count)

            // ── Calendar (EventKit) ──────────────────────────────────────

            case "create_event":
                guard let title = requiredArgument("title", in: toolCall.arguments),
                      let startDate = requiredArgument("start_date", in: toolCall.arguments) else {
                    return "Error: create_event requires 'title' and 'start_date'."
                }
                let allDay = toolCall.arguments["all_day"]?.lowercased() == "true"
                return await phoneModeManager.createEvent(
                    title: title,
                    startDate: startDate,
                    endDate: toolCall.arguments["end_date"],
                    location: toolCall.arguments["location"],
                    notes: toolCall.arguments["notes"],
                    allDay: allDay
                )

            case "list_events":
                let daysStr = toolCall.arguments["days_ahead"] ?? "7"
                let days = Int(daysStr) ?? 7
                return await phoneModeManager.listEvents(daysAhead: days)

            // ── Open App / URL ───────────────────────────────────────────

            case "open_url":
                guard let url = requiredArgument("url", in: toolCall.arguments) else {
                    return "Error: open_url requires 'url'."
                }
                return await MainActor.run { phoneModeManager.openURL(urlString: url) }

            case "open_maps":
                guard let query = requiredArgument("query", in: toolCall.arguments) else {
                    return "Error: open_maps requires 'query'."
                }
                return await MainActor.run { phoneModeManager.openMaps(query: query) }

            case "open_maps_directions":
                guard let dest = requiredArgument("destination", in: toolCall.arguments) else {
                    return "Error: open_maps_directions requires 'destination'."
                }
                return await MainActor.run { phoneModeManager.openMapsDirections(destination: dest) }

            // ── Shortcuts ────────────────────────────────────────────────

            case "run_shortcut":
                guard let name = requiredArgument("name", in: toolCall.arguments) else {
                    return "Error: run_shortcut requires 'name'."
                }
                return await MainActor.run { phoneModeManager.runShortcut(name: name) }

            case "save_shortcuts_to_memory":
                guard let names = requiredArgument("names", in: toolCall.arguments) else {
                    return "Error: save_shortcuts_to_memory requires 'names'."
                }
                return phoneModeManager.saveShortcutsToMemory(names: names)

            default:
                AppLogger.warning("Unknown tool requested: \(toolCall.name)", category: .agent)
                return "Error: Unknown tool '\(toolCall.name)'."
            }
        } catch {
            AppLogger.error("Tool execution failed for \(toolCall.name): \(error.localizedDescription)", category: .agent)
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Memory Search

    private func searchMemoryFiles(query: String) -> String {
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

    // MARK: - Date Parsing

    private func parseDueDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty, value.lowercased() != "unscheduled" else {
            return nil
        }

        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // "in X minutes/hours/days"
        if let match = lower.range(of: #"in\s+(\d+)\s+(minute|min|hour|hr|day)"#, options: .regularExpression) {
            let matched = String(lower[match])
            let digits = matched.replacingOccurrences(of: #"[^\d]"#, with: "", options: .regularExpression)
            guard let amount = Int(digits) else { return nil }

            if matched.contains("min") {
                return Date().addingTimeInterval(TimeInterval(amount * 60))
            } else if matched.contains("hour") || matched.contains("hr") {
                return Date().addingTimeInterval(TimeInterval(amount * 3600))
            } else if matched.contains("day") {
                return Date().addingTimeInterval(TimeInterval(amount * 86400))
            }
        }

        // "tomorrow"
        if lower.contains("tomorrow") {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }

        // ISO 8601 / standard date formats
        let formatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm",
                "yyyy-MM-dd",
                "MM/dd/yyyy HH:mm",
                "MM/dd/yyyy"
            ]
            return formats.map { fmt in
                let f = DateFormatter()
                f.dateFormat = fmt
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }
        }()

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Tool Call Extraction

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
        let names = looseToolNamePattern
        let pattern = #"(?s)```(?:json)?\s*(\{.*?"name"\s*:\s*"(?:"# + names + #")".*?"arguments"\s*:\s*\{.*?\}\s*\})\s*```|\{[^{}]*"name"\s*:\s*"(?:"# + names + #")"[^{}]*"arguments"\s*:\s*\{.*?\}\s*\}"#
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

            let argumentsAny = (json["arguments"] as? [String: Any])
                ?? (json["args"] as? [String: Any])
                ?? [:]
            var arguments: [String: String] = [:]
            for (key, value) in argumentsAny {
                arguments[key] = stringifyJSONValue(value)
            }

            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else { continue }
            return ToolCall(name: normalizedName, arguments: arguments)
        }

        return nil
    }

    // MARK: - JSON Helpers

    private func jsonCandidates(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedBackslashes = sanitizeJSONString(trimmed)
        let withoutTrailingCommas = sanitizedBackslashes.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )
        let extractedFromTrimmed = extractFirstJSONObject(from: trimmed)
        let extractedFromSanitized = extractFirstJSONObject(from: sanitizedBackslashes)

        var candidates: [String] = []
        for candidate in [trimmed, sanitizedBackslashes, withoutTrailingCommas, extractedFromTrimmed, extractedFromSanitized] {
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
            return restoreLikelyBackslashEscapes(in: string)
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
            return restoreLikelyBackslashEscapes(in: string)
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: []),
           let string = String(data: data, encoding: .utf8) {
            return restoreLikelyBackslashEscapes(in: string)
        }
        return restoreLikelyBackslashEscapes(in: String(describing: value))
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

    private func extractFirstJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{") else {
            return text
        }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: index)
                        return String(text[start..<end])
                    }
                }
            }

            index = text.index(after: index)
        }

        return text
    }

    private func restoreLikelyBackslashEscapes(in value: String) -> String {
        guard !value.isEmpty else { return value }
        var output = ""
        for character in value {
            switch character {
            case "\u{0008}": output += "\\b"
            case "\u{0009}": output += "\\t"
            case "\u{000C}": output += "\\f"
            case "\u{000D}": output += "\\r"
            default: output.append(character)
            }
        }
        return output
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
