import Foundation

struct CreateTaskTool: Tool {
    let name = "create_task"
    let description = "Create a task"
    let parameters = ["title", "due?", "details?"]
    let taskManager: TaskManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        let details = arguments["details"] ?? ""
        let dueDateStr = arguments["due"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let dueDate: Date?
        if let value = dueDateStr, !value.isEmpty, value.lowercased() != "unscheduled" {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            let matches = detector?.matches(in: value, options: [], range: NSRange(location: 0, length: value.utf16.count))
            dueDate = matches?.first?.date
        } else {
            dueDate = nil
        }
        
        let task = taskManager.addTask(title: title, details: details, dueDate: dueDate)
        let dueStr = task.dueDate.map {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return " (due: \(f.string(from: $0)))"
        } ?? ""
        AppLogger.info("Tool executed: create_task title=\(title)", category: .agent)
        return "Task created: \(title)\(dueStr)"
    }
}

struct ListTasksTool: Tool {
    let name = "list_tasks"
    let description = "List all tasks"
    let parameters = ["include_completed?"]
    let taskManager: TaskManager

    func execute(arguments: [String: String]) async throws -> String {
        let includeCompleted = arguments["include_completed"]?.lowercased() == "true"
        AppLogger.info("Tool executed: list_tasks", category: .agent)
        return taskManager.listTasks(includeCompleted: includeCompleted)
    }
}

struct CompleteTaskTool: Tool {
    let name = "complete_task"
    let description = "Complete a task by title"
    let parameters = ["title"]
    let taskManager: TaskManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        AppLogger.info("Tool executed: complete_task title=\(title)", category: .agent)
        return taskManager.completeTask(matching: title)
    }
}
