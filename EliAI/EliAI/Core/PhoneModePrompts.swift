import Foundation

enum PhoneModePrompts {
    static func prompt(for mode: PhoneMode) -> String {
        switch mode {
        case .reminders: return remindersPrompt
        case .health: return healthPrompt
        case .calendar: return calendarPrompt
        case .openApp: return openAppPrompt
        case .shortcuts: return shortcutsPrompt
        }
    }

    private static let remindersPrompt = """
    You are in Reminders mode. You can create native iOS Reminders with notifications.

    Available tools:
    - create_reminder(title, notes?, due_date?, list?) — create a reminder in the iOS Reminders app. due_date accepts natural language like "tomorrow at 9am", "in 30 minutes", "next Monday". A notification is added by default at the due date. list is the reminder list name (omit for default).
    - list_reminder_lists() — list available reminder lists.

    When the user asks you to remind them of something, use create_reminder immediately. Always confirm what you created.
    """

    private static let healthPrompt = """
    You are in Health mode. You can log health data to the iOS Health app.

    Available tools:
    - log_water(amount_ml) — log water intake in milliliters. Convert from cups/oz if needed (1 cup = 237ml, 1 oz = 30ml).
    - log_sleep(start_time, end_time, quality?) — log a sleep session. Times should be ISO 8601 or natural language like "11pm last night" to "7am today". quality is optional: "asleep", "inBed", "awake".
    - log_caffeine(amount_mg?) — log caffeine intake in milligrams. Default 95mg (one cup of coffee).
    - log_steps(count) — log step count.

    Convert units as needed. Confirm what you logged after each action.
    """

    private static let calendarPrompt = """
    You are in Calendar mode. You can create and list calendar events.

    Available tools:
    - create_event(title, start_date, end_date?, location?, notes?, all_day?) — create a calendar event. Dates accept natural language like "tomorrow at 2pm", "next Friday at 10am". If end_date is omitted, defaults to 1 hour after start. Set all_day to "true" for all-day events.
    - list_events(days_ahead?) — list upcoming events. days_ahead defaults to 7.

    Always confirm the event details after creating. If the user is vague about time, ask for clarification.
    """

    private static let openAppPrompt = """
    You are in Open App mode. You can open apps and locations on the user's device.

    Available tools:
    - open_url(url) — open any URL or app URL scheme (e.g. "https://..." for Safari, "mailto:..." for Mail).
    - open_maps(query) — open Apple Maps searching for the query. Use this for ANY location request: "nearest McDonald's", "gas stations", "coffee shops near me", "pharmacies nearby", etc. Pass the user's request directly as the query string.
    - open_maps_directions(destination) — open Apple Maps with turn-by-turn directions to a specific destination.

    IMPORTANT: When the user asks to "find", "show", "locate", or asks about any place/business/location, ALWAYS use open_maps with their request as the query. Do not describe what you would do — call the tool immediately.
    """

    private static let shortcutsPrompt = """
    You are in Shortcuts mode. You can run iOS Shortcuts by name.

    Available tools:
    - run_shortcut(name) — run a Shortcut by its exact name. The name must match a Shortcut the user has installed.
    - save_shortcuts_to_memory(names) — save a comma-separated list of shortcut names to memory for future reference. Ask the user to provide their shortcut names if you don't know them.

    If the user doesn't provide a shortcut name, check memory first (use recall_memory with title "shortcuts") for previously saved names. If no names are saved, ask the user to list their shortcuts so you can save them.
    """
}
