import Foundation
import EventKit
import HealthKit
import UIKit
import Observation

@Observable
class PhoneModeManager {
    private let eventStore = EKEventStore()
    private let healthStore = HKHealthStore()
    private let fileSystem: FileSystemManager

    private(set) var remindersAuthorized = false
    private(set) var calendarAuthorized = false
    private(set) var healthAuthorized = false

    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }

    // MARK: - Permissions

    func requestRemindersAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            await MainActor.run { remindersAuthorized = granted }
            return granted
        } catch {
            AppLogger.error("Reminders access error: \(error.localizedDescription)", category: .agent)
            return false
        }
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run { calendarAuthorized = granted }
            return granted
        } catch {
            AppLogger.error("Calendar access error: \(error.localizedDescription)", category: .agent)
            return false
        }
    }

    func requestHealthAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let writeTypes: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .dietaryWater)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: [])
            await MainActor.run { healthAuthorized = true }
            return true
        } catch {
            AppLogger.error("HealthKit access error: \(error.localizedDescription)", category: .agent)
            return false
        }
    }

    // MARK: - Reminders (EventKit)

    func createReminder(title: String, notes: String?, dueDateString: String?, list: String?) async -> String {
        guard await requestRemindersAccess() else {
            return "Error: Reminders access denied. Please allow in Settings."
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes

        if let listName = list {
            let calendars = eventStore.calendars(for: .reminder)
            if let matching = calendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                reminder.calendar = matching
            } else {
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
            }
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        if let dateStr = dueDateString, let date = parseDateString(dateStr) {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            reminder.dueDateComponents = components
            let alarm = EKAlarm(absoluteDate: date)
            reminder.addAlarm(alarm)
        }

        do {
            try eventStore.save(reminder, commit: true)
            let dueInfo = dueDateString.map { " (due: \($0))" } ?? ""
            AppLogger.info("Reminder created: \(title)\(dueInfo)", category: .agent)
            return "Reminder created: \(title)\(dueInfo)"
        } catch {
            AppLogger.error("Failed to create reminder: \(error.localizedDescription)", category: .agent)
            return "Error creating reminder: \(error.localizedDescription)"
        }
    }

    func listReminderLists() async -> String {
        guard await requestRemindersAccess() else {
            return "Error: Reminders access denied."
        }

        let calendars = eventStore.calendars(for: .reminder)
        if calendars.isEmpty {
            return "No reminder lists found."
        }
        return calendars.enumerated().map { i, cal in
            "\(i + 1). \(cal.title)"
        }.joined(separator: "\n")
    }

    // MARK: - Health (HealthKit)

    func logWater(amountML: Double) async -> String {
        guard await requestHealthAccess() else {
            return "Error: Health access denied. Please allow in Settings."
        }

        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            return "Error: Water data type not available."
        }

        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountML)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            AppLogger.info("Logged water: \(amountML)ml", category: .agent)
            return "Logged \(Int(amountML))ml of water to Health."
        } catch {
            return "Error logging water: \(error.localizedDescription)"
        }
    }

    func logSleep(startTime: String, endTime: String, quality: String?) async -> String {
        guard await requestHealthAccess() else {
            return "Error: Health access denied."
        }

        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return "Error: Sleep data type not available."
        }

        guard let start = parseDateString(startTime), let end = parseDateString(endTime) else {
            return "Error: Could not parse sleep times. Use format like '11pm last night' or '2025-03-06T23:00:00'."
        }

        let value: HKCategoryValueSleepAnalysis
        switch quality?.lowercased() {
        case "awake": value = .awake
        case "inbed", "in bed": value = .inBed
        default: value = .asleepUnspecified
        }

        let sample = HKCategorySample(
            type: sleepType,
            value: value.rawValue,
            start: start,
            end: end
        )

        do {
            try await healthStore.save(sample)
            let duration = end.timeIntervalSince(start) / 3600
            AppLogger.info("Logged sleep: \(String(format: "%.1f", duration))h", category: .agent)
            return "Logged \(String(format: "%.1f", duration)) hours of sleep to Health."
        } catch {
            return "Error logging sleep: \(error.localizedDescription)"
        }
    }

    func logCaffeine(amountMG: Double) async -> String {
        guard await requestHealthAccess() else {
            return "Error: Health access denied."
        }

        guard let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else {
            return "Error: Caffeine data type not available."
        }

        let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: amountMG)
        let sample = HKQuantitySample(type: caffeineType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            AppLogger.info("Logged caffeine: \(amountMG)mg", category: .agent)
            return "Logged \(Int(amountMG))mg of caffeine to Health."
        } catch {
            return "Error logging caffeine: \(error.localizedDescription)"
        }
    }

    func logSteps(count: Int) async -> String {
        guard await requestHealthAccess() else {
            return "Error: Health access denied."
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return "Error: Step data type not available."
        }

        let quantity = HKQuantity(unit: .count(), doubleValue: Double(count))
        let sample = HKQuantitySample(type: stepType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            AppLogger.info("Logged steps: \(count)", category: .agent)
            return "Logged \(count) steps to Health."
        } catch {
            return "Error logging steps: \(error.localizedDescription)"
        }
    }

    // MARK: - Calendar (EventKit)

    func createEvent(title: String, startDate: String, endDate: String?, location: String?, notes: String?, allDay: Bool) async -> String {
        guard await requestCalendarAccess() else {
            return "Error: Calendar access denied. Please allow in Settings."
        }

        guard let start = parseDateString(startDate) else {
            return "Error: Could not parse start date '\(startDate)'."
        }

        let end: Date
        if let endStr = endDate, let parsed = parseDateString(endStr) {
            end = parsed
        } else {
            end = start.addingTimeInterval(3600)
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.location = location
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = allDay ? .none : .short
            let dateStr = formatter.string(from: start)
            AppLogger.info("Event created: \(title) on \(dateStr)", category: .agent)
            return "Event created: \(title) on \(dateStr)"
        } catch {
            return "Error creating event: \(error.localizedDescription)"
        }
    }

    func listEvents(daysAhead: Int) async -> String {
        guard await requestCalendarAccess() else {
            return "Error: Calendar access denied."
        }

        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        let predicate = eventStore.predicateForEvents(withStart: now, end: future, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            return "No events in the next \(daysAhead) days."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return events.prefix(20).enumerated().map { i, event in
            let date = event.isAllDay ? "All day" : formatter.string(from: event.startDate)
            let loc = event.location.map { " (\($0))" } ?? ""
            return "\(i + 1). \(event.title ?? "Untitled") — \(date)\(loc)"
        }.joined(separator: "\n")
    }

    // MARK: - Open App / URL

    @MainActor
    func openURL(urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "Error: Invalid URL '\(urlString)'."
        }

        UIApplication.shared.open(url)
        AppLogger.info("Opened URL: \(urlString)", category: .agent)
        return "Opened: \(urlString)"
    }

    @MainActor
    func openMaps(query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "maps://?q=\(encoded)"
        guard let url = URL(string: urlString) else {
            return "Error: Could not build Maps URL for '\(query)'."
        }

        UIApplication.shared.open(url)
        AppLogger.info("Opened Maps search: \(query)", category: .agent)
        return "Opened Maps searching for: \(query)"
    }

    @MainActor
    func openMapsDirections(destination: String) -> String {
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        let urlString = "maps://?daddr=\(encoded)"
        guard let url = URL(string: urlString) else {
            return "Error: Could not build Maps URL for '\(destination)'."
        }

        UIApplication.shared.open(url)
        AppLogger.info("Opened Maps directions to: \(destination)", category: .agent)
        return "Opened Maps with directions to: \(destination)"
    }

    // MARK: - Shortcuts

    @MainActor
    func runShortcut(name: String) -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlString = "shortcuts://run-shortcut?name=\(encoded)"
        guard let url = URL(string: urlString) else {
            return "Error: Could not build Shortcuts URL for '\(name)'."
        }

        UIApplication.shared.open(url)
        AppLogger.info("Running shortcut: \(name)", category: .agent)
        return "Running shortcut: \(name)"
    }

    func saveShortcutsToMemory(names: String) -> String {
        do {
            try fileSystem.createFile(path: "memory/shortcuts.md", content: "# Saved Shortcuts\n\n\(names)")
            AppLogger.info("Saved shortcut names to memory", category: .agent)
            return "Saved shortcut names to memory. I can reference these when you ask me to run a shortcut."
        } catch {
            return "Error saving shortcuts: \(error.localizedDescription)"
        }
    }

    // MARK: - Date Parsing

    private func parseDateString(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }

        return parseNaturalDate(trimmed)
    }

    private func parseNaturalDate(_ input: String) -> Date? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let calendar = Calendar.current

        if let range = lower.range(of: #"in\s+(\d+)\s*(minute|min|hour|hr|day)"#, options: .regularExpression) {
            let match = String(lower[range])
            let digits = match.filter { $0.isNumber }
            guard let value = Int(digits) else { return nil }

            if match.contains("minute") || match.contains("min") {
                return calendar.date(byAdding: .minute, value: value, to: now)
            } else if match.contains("hour") || match.contains("hr") {
                return calendar.date(byAdding: .hour, value: value, to: now)
            } else if match.contains("day") {
                return calendar.date(byAdding: .day, value: value, to: now)
            }
        }

        if lower.contains("tomorrow") {
            var date = calendar.date(byAdding: .day, value: 1, to: now)!
            if let time = extractTime(from: lower) {
                date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date)!
            } else {
                date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
            }
            return date
        }

        if lower.contains("today") {
            if let time = extractTime(from: lower) {
                return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now)
            }
        }

        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                        "thursday": 5, "friday": 6, "saturday": 7]
        for (name, weekday) in weekdays {
            if lower.contains(name) || lower.contains(String(name.prefix(3))) {
                let current = calendar.component(.weekday, from: now)
                var diff = weekday - current
                if diff <= 0 { diff += 7 }
                if lower.contains("next") { diff += 7 }
                var date = calendar.date(byAdding: .day, value: diff, to: now)!
                if let time = extractTime(from: lower) {
                    date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date)!
                } else {
                    date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
                }
                return date
            }
        }

        if let time = extractTime(from: lower) {
            var date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now)!
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
            return date
        }

        return nil
    }

    private func extractTime(from text: String) -> (hour: Int, minute: Int)? {
        let patterns = [
            #"(\d{1,2}):(\d{2})\s*(am|pm)"#,
            #"(\d{1,2})\s*(am|pm)"#,
            #"(\d{1,2}):(\d{2})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange) else { continue }

            if match.numberOfRanges >= 4, let hRange = Range(match.range(at: 1), in: text),
               let mRange = Range(match.range(at: 2), in: text),
               let pRange = Range(match.range(at: 3), in: text) {
                var hour = Int(text[hRange]) ?? 0
                let minute = Int(text[mRange]) ?? 0
                let period = text[pRange].lowercased()
                if period == "pm" && hour < 12 { hour += 12 }
                if period == "am" && hour == 12 { hour = 0 }
                return (hour, minute)
            }

            if match.numberOfRanges >= 3 {
                if let hRange = Range(match.range(at: 1), in: text),
                   let pRange = Range(match.range(at: 2), in: text),
                   text[pRange].lowercased().hasSuffix("m") {
                    var hour = Int(text[hRange]) ?? 0
                    let period = text[pRange].lowercased()
                    if period == "pm" && hour < 12 { hour += 12 }
                    if period == "am" && hour == 12 { hour = 0 }
                    return (hour, 0)
                }

                if let hRange = Range(match.range(at: 1), in: text),
                   let mRange = Range(match.range(at: 2), in: text) {
                    let hour = Int(text[hRange]) ?? 0
                    let minute = Int(text[mRange]) ?? 0
                    return (hour, minute)
                }
            }
        }

        return nil
    }
}
