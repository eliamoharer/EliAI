import Foundation

struct CreateReminderTool: Tool {
    let name = "create_reminder"
    let description = "Create a reminder in EventKit"
    let parameters = ["title", "notes?", "due_date?", "list?"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        return try await phoneModeManager.createReminder(
            title: title,
            notes: arguments["notes"],
            dueDateString: arguments["due_date"],
            list: arguments["list"]
        )
    }
}

struct ListReminderListsTool: Tool {
    let name = "list_reminder_lists"
    let description = "List available reminder lists"
    let parameters = []
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        return try await phoneModeManager.listReminderLists()
    }
}

struct CreateEventTool: Tool {
    let name = "create_event"
    let description = "Create an event in EventKit"
    let parameters = ["title", "start_date", "end_date?", "location?", "notes?", "all_day?"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { throw ToolError.missingArgument("title") }
        guard let startDate = arguments["start_date"]?.trimmingCharacters(in: .whitespacesAndNewlines), !startDate.isEmpty else { throw ToolError.missingArgument("start_date") }
        let allDay = arguments["all_day"]?.lowercased() == "true"
        return try await phoneModeManager.createEvent(
            title: title,
            startDate: startDate,
            endDate: arguments["end_date"],
            location: arguments["location"],
            notes: arguments["notes"],
            allDay: allDay
        )
    }
}

struct ListEventsTool: Tool {
    let name = "list_events"
    let description = "List events in EventKit"
    let parameters = ["days_ahead?"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        let daysStr = arguments["days_ahead"] ?? "7"
        let days = Int(daysStr) ?? 7
        return try await phoneModeManager.listEvents(daysAhead: days)
    }
}

struct OpenUrlTool: Tool {
    let name = "open_url"
    let description = "Open a URL"
    let parameters = ["url"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let url = arguments["url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { throw ToolError.missingArgument("url") }
        return try await MainActor.run { try phoneModeManager.openURL(urlString: url) }
    }
}

struct OpenMapsTool: Tool {
    let name = "open_maps"
    let description = "Open Apple Maps with a query"
    let parameters = ["query"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let query = arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { throw ToolError.missingArgument("query") }
        return try await MainActor.run { try phoneModeManager.openMaps(query: query) }
    }
}

struct OpenMapsDirectionsTool: Tool {
    let name = "open_maps_directions"
    let description = "Open Apple Maps with directions to a destination"
    let parameters = ["destination"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let dest = arguments["destination"]?.trimmingCharacters(in: .whitespacesAndNewlines), !dest.isEmpty else { throw ToolError.missingArgument("destination") }
        return try await MainActor.run { try phoneModeManager.openMapsDirections(destination: dest) }
    }
}

struct RunShortcutTool: Tool {
    let name = "run_shortcut"
    let description = "Run an Apple Shortcut"
    let parameters = ["name"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let name = arguments["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw ToolError.missingArgument("name") }
        return try await MainActor.run { try phoneModeManager.runShortcut(name: name) }
    }
}

struct SaveShortcutsTool: Tool {
    let name = "save_shortcuts_to_memory"
    let description = "Save shortcut names to memory"
    let parameters = ["names"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let names = arguments["names"]?.trimmingCharacters(in: .whitespacesAndNewlines), !names.isEmpty else { throw ToolError.missingArgument("names") }
        return try phoneModeManager.saveShortcutsToMemory(names: names)
    }
}
