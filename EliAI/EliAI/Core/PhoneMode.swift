import SwiftUI

enum PhoneMode: String, CaseIterable, Identifiable {
    case reminders
    case health
    case calendar
    case openApp
    case shortcuts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reminders: return "Reminders"
        case .health: return "Health"
        case .calendar: return "Calendar"
        case .openApp: return "Open App"
        case .shortcuts: return "Shortcuts"
        }
    }

    var iconName: String {
        switch self {
        case .reminders: return "bell.fill"
        case .health: return "heart.fill"
        case .calendar: return "calendar"
        case .openApp: return "arrow.up.forward.app.fill"
        case .shortcuts: return "bolt.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .reminders: return Color(red: 0.95, green: 0.85, blue: 0.45)
        case .health: return Color(red: 0.95, green: 0.55, blue: 0.55)
        case .calendar: return Color(red: 0.55, green: 0.72, blue: 0.95)
        case .openApp: return Color(red: 0.55, green: 0.88, blue: 0.62)
        case .shortcuts: return Color(red: 0.75, green: 0.60, blue: 0.95)
        }
    }

    var toolNames: Set<String> {
        switch self {
        case .reminders: return ["create_reminder", "list_reminder_lists"]
        case .health: return ["log_water", "log_sleep", "log_caffeine", "log_steps"]
        case .calendar: return ["create_event", "list_events"]
        case .openApp: return ["open_url", "open_maps", "open_maps_directions"]
        case .shortcuts: return ["run_shortcut", "save_shortcuts_to_memory"]
        }
    }
}
