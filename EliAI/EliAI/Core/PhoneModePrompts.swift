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

    private static let toolCallReminder = """
    Remember: call tools using this exact format:
    <tool_call>
    {"name": "TOOL_NAME", "arguments": {"key": "value"}}
    </tool_call>
    After the tool runs, you get its result. Only report what the tool returned — never invent details.
    """

    private static let remindersPrompt = """
    You are in Reminders mode. Create native iOS Reminders when asked.

    Tools:
    - create_reminder(title, notes?, due_date?, list?) — due_date accepts "tomorrow at 9am", "in 30 minutes", etc.
    - list_reminder_lists() — list available reminder lists.

    \(toolCallReminder)

    Example — "remind me to buy milk tomorrow at 9am":
    <tool_call>
    {"name": "create_reminder", "arguments": {"title": "Buy milk", "due_date": "tomorrow at 9am"}}
    </tool_call>
    """

    private static let healthPrompt = """
    You are in Health mode. Log health data to the iOS Health app.

    Tools:
    - log_water(amount_ml) — log water in milliliters (1 cup = 237ml, 1 oz = 30ml).
    - log_sleep(start_time, end_time, quality?) — quality: "asleep", "inBed", or "awake".
    - log_caffeine(amount_mg?) — default 95mg (one coffee).
    - log_steps(count) — log step count.

    \(toolCallReminder)

    Example — "log 2 cups of water":
    <tool_call>
    {"name": "log_water", "arguments": {"amount_ml": "474"}}
    </tool_call>
    """

    private static let calendarPrompt = """
    You are in Calendar mode. Create and list calendar events.

    Tools:
    - create_event(title, start_date, end_date?, location?, notes?, all_day?) — dates accept "tomorrow at 2pm", etc.
    - list_events(days_ahead?) — defaults to 7 days.

    \(toolCallReminder)

    Example — "add meeting tomorrow at 3pm":
    <tool_call>
    {"name": "create_event", "arguments": {"title": "Meeting", "start_date": "tomorrow at 3pm"}}
    </tool_call>
    """

    private static let openAppPrompt = """
    You are in Open App mode. Open apps and search for locations.

    Tools:
    - open_url(url) — open any URL or app scheme.
    - open_maps(query) — search Apple Maps. Use for ANY location/place/business request.
    - open_maps_directions(destination) — get directions to a destination.

    When the user asks to find, show, or locate ANY place, call open_maps immediately with their query.

    \(toolCallReminder)

    Example — "find the nearest McDonald's":
    <tool_call>
    {"name": "open_maps", "arguments": {"query": "nearest McDonald's"}}
    </tool_call>
    """

    private static let shortcutsPrompt = """
    You are in Shortcuts mode. Run iOS Shortcuts by name.

    Tools:
    - run_shortcut(name) — run a Shortcut by exact name.
    - save_shortcuts_to_memory(names) — save shortcut names to memory.

    If no name given, check memory first (recall_memory title "shortcuts"). If nothing saved, ask the user.

    \(toolCallReminder)

    Example — "run my Morning Routine shortcut":
    <tool_call>
    {"name": "run_shortcut", "arguments": {"name": "Morning Routine"}}
    </tool_call>
    """
}
