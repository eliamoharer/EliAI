import SwiftUI
import UIKit

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
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkUIColor : lightUIColor
        })
    }

    private var lightUIColor: UIColor {
        switch self {
        case .reminders: return UIColor(red: 0.72, green: 0.58, blue: 0.10, alpha: 1)
        case .health:    return UIColor(red: 0.78, green: 0.30, blue: 0.30, alpha: 1)
        case .calendar:  return UIColor(red: 0.25, green: 0.48, blue: 0.82, alpha: 1)
        case .openApp:   return UIColor(red: 0.22, green: 0.62, blue: 0.35, alpha: 1)
        case .shortcuts: return UIColor(red: 0.52, green: 0.36, blue: 0.78, alpha: 1)
        }
    }

    private var darkUIColor: UIColor {
        switch self {
        case .reminders: return UIColor(red: 0.95, green: 0.85, blue: 0.45, alpha: 1)
        case .health:    return UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1)
        case .calendar:  return UIColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1)
        case .openApp:   return UIColor(red: 0.55, green: 0.88, blue: 0.62, alpha: 1)
        case .shortcuts: return UIColor(red: 0.75, green: 0.60, blue: 0.95, alpha: 1)
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
