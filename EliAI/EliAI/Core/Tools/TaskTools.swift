import Foundation

struct ScheduleNotificationTool: Tool {
    let name = "schedule_notification"
    let description = "Schedule a push notification for a specific time"
    let parameters = ["title", "due", "details?"]
    let taskManager: TaskManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        let details = arguments["details"] ?? ""
        let dueDateStr = arguments["due"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let value = dueDateStr, !value.isEmpty, value.lowercased() != "unscheduled" else {
            throw ToolError.missingArgument("due")
        }
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: value, options: [], range: NSRange(location: 0, length: value.utf16.count))
        guard let dueDate = matches?.first?.date else {
            throw ToolError.invalidArgument("due", expected: "a valid natural language date or time")
        }
        
        let task = taskManager.addTask(title: title, details: details, dueDate: dueDate)
        let dueStr = task.dueDate.map {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return " (scheduled for: \(f.string(from: $0)))"
        } ?? ""
        AppLogger.info("Tool executed: schedule_notification title=\(title)", category: .agent)
        return "Notification scheduled: \(title)\(dueStr)"
    }
}

struct ListNotificationsTool: Tool {
    let name = "list_notifications"
    let description = "List all scheduled notifications"
    let parameters = ["include_completed?"]
    let taskManager: TaskManager

    func execute(arguments: [String: String]) async throws -> String {
        let includeCompleted = arguments["include_completed"]?.lowercased() == "true"
        AppLogger.info("Tool executed: list_notifications", category: .agent)
        return taskManager.listTasks(includeCompleted: includeCompleted)
    }
}

struct CancelNotificationTool: Tool {
    let name = "cancel_notification"
    let description = "Cancel a scheduled notification by title"
    let parameters = ["title"]
    let taskManager: TaskManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        AppLogger.info("Tool executed: cancel_notification title=\(title)", category: .agent)
        return taskManager.completeTask(matching: title)
    }
}
