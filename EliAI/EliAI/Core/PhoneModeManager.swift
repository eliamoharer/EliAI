import Foundation
import EventKit
import HealthKit
import UIKit
import Observation

@Observable
class PhoneModeManager {
    private let eventStore = EKEventStore()
    private var _healthStore: HKHealthStore?
    private let fileSystem: FileSystemManager

    private(set) var remindersAuthorized = false
    private(set) var calendarAuthorized = false
    private(set) var healthAuthorized = false

    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
        if HKHealthStore.isHealthDataAvailable() {
            _healthStore = HKHealthStore()
        }
    }

    private var healthStore: HKHealthStore? { _healthStore }

    // MARK: - Permissions

    func requestRemindersAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess { 
            await MainActor.run { remindersAuthorized = true }
            return true 
        }
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
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            await MainActor.run { calendarAuthorized = true }
            return true
        }
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
            AppLogger.error("HealthKit not available on this device", category: .agent)
            return false
        }
        guard let healthStore else {
            AppLogger.error("HealthKit store not initialized", category: .agent)
            return false
        }

        var writeTypes = Set<HKSampleType>()
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) { writeTypes.insert(water) }
        if let caffeine = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) { writeTypes.insert(caffeine) }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { writeTypes.insert(steps) }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { writeTypes.insert(sleep) }

        guard !writeTypes.isEmpty else { return false }

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: [])
            
            var authorized = false
            for type in writeTypes {
                let status = healthStore.authorizationStatus(for: type)
                AppLogger.info("HealthKit auth status for \(type.identifier): \(status.rawValue)", category: .agent)
                if status == .sharingAuthorized {
                    authorized = true
                }
            }
            await MainActor.run { healthAuthorized = authorized }
            return authorized
        } catch {
            AppLogger.error("HealthKit authorization error: \(error.localizedDescription)", category: .agent)
            return false
        }
    }

    func requestAllPermissions() async {
        _ = await requestRemindersAccess()
        _ = await requestCalendarAccess()
        _ = await requestHealthAccess()
    }

    func preauthorize(for mode: PhoneMode) async {
        switch mode {
        case .reminders:
            _ = await requestRemindersAccess()
        case .calendar:
            _ = await requestCalendarAccess()
        case .health:
            _ = await requestHealthAccess()
        default:
            break
        }
    }

    // MARK: - Reminders (EventKit)

    func createReminder(title: String, notes: String?, dueDateString: String?, list: String?) async throws -> String {
        guard await requestRemindersAccess() else {
            throw ToolError.unauthorized("Reminders access denied. Please allow in Settings.")
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
            throw ToolError.executionFailed("Error creating reminder: \(error.localizedDescription)")
        }
    }

    func listReminderLists() async throws -> String {
        guard await requestRemindersAccess() else {
            throw ToolError.unauthorized("Reminders access denied.")
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

    func logWater(amountML: Double) async throws -> String {
        guard await requestHealthAccess(), let healthStore else {
            throw ToolError.unauthorized("Health access denied. Go to Settings > Privacy & Security > Health > EliAI and enable all categories. If EliAI doesn't appear there, the HealthKit entitlement may need to be configured in your Apple Developer account.")
        }

        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            throw ToolError.executionFailed("Water data type not available.")
        }

        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountML)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            AppLogger.info("Logged water: \(amountML)ml", category: .agent)
            return "Logged \(Int(amountML))ml of water to Health."
        } catch {
            throw ToolError.executionFailed("Error logging water: \(error.localizedDescription)")
        }
    }

    func logSleep(startTime: String, endTime: String, quality: String?) async throws -> String {
        guard await requestHealthAccess(), let healthStore else {
            throw ToolError.unauthorized("Health access denied. Go to Settings > Privacy & Security > Health > EliAI and enable all categories. If EliAI doesn't appear there, the HealthKit entitlement may need to be configured in your Apple Developer account.")
        }

        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw ToolError.executionFailed("Sleep data type not available.")
        }

        guard let start = parseDateString(startTime), let end = parseDateString(endTime) else {
            throw ToolError.invalidArgument("start_time/end_time", expected: "time format like '11pm last night' or '2025-03-06T23:00:00'")
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
            throw ToolError.executionFailed("Error logging sleep: \(error.localizedDescription)")
        }
    }

    func logCaffeine(amountMG: Double) async throws -> String {
        guard await requestHealthAccess(), let healthStore else {
            throw ToolError.unauthorized("Health access denied. Go to Settings > Privacy & Security > Health > EliAI and enable all categories. If EliAI doesn't appear there, the HealthKit entitlement may need to be configured in your Apple Developer account.")
        }

        guard let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else {
            throw ToolError.executionFailed("Caffeine data type not available.")
        }

        let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: amountMG)
        let sample = HKQuantitySample(type: caffeineType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            AppLogger.info("Logged caffeine: \(amountMG)mg", category: .agent)
            return "Logged \(Int(amountMG))mg of caffeine to Health."
        } catch {
            throw ToolError.executionFailed("Error logging caffeine: \(error.localizedDescription)")
        }
    }

    func logSteps(count: Int) async throws -> String {
        guard await requestHealthAccess(), let healthStore else {
            throw ToolError.unauthorized("Health access denied. Go to Settings > Privacy & Security > Health > EliAI and enable all categories. If EliAI doesn't appear there, the HealthKit entitlement may need to be configured in your Apple Developer account.")
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw ToolError.executionFailed("Step data type not available.")
        }

        let quantity = HKQuantity(unit: .count(), doubleValue: Double(count))
        let sample = HKQuantitySample(type: stepType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            AppLogger.info("Logged steps: \(count)", category: .agent)
            return "Logged \(count) steps to Health."
        } catch {
            throw ToolError.executionFailed("Error logging steps: \(error.localizedDescription)")
        }
    }

    // MARK: - Calendar (EventKit)

    func createEvent(title: String, startDate: String, endDate: String?, location: String?, notes: String?, allDay: Bool) async throws -> String {
        guard await requestCalendarAccess() else {
            throw ToolError.unauthorized("Calendar access denied. Please allow in Settings.")
        }

        guard let start = parseDateString(startDate) else {
            throw ToolError.invalidArgument("start_date", expected: "valid date/time format")
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
            throw ToolError.executionFailed("Error creating event: \(error.localizedDescription)")
        }
    }

    func listEvents(daysAhead: Int) async throws -> String {
        guard await requestCalendarAccess() else {
            throw ToolError.unauthorized("Calendar access denied.")
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
    func openURL(urlString: String) throws -> String {
        guard let url = URL(string: urlString) else {
            throw ToolError.invalidArgument("url", expected: "valid URL")
        }

        UIApplication.shared.open(url)
        AppLogger.info("Opened URL: \(urlString)", category: .agent)
        return "Done — opened \(urlString) on the device."
    }

    @MainActor
    func openMaps(query: String) throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "maps://?q=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw ToolError.invalidArgument("query", expected: "valid string for Maps URL")
        }

        UIApplication.shared.open(url)
        AppLogger.info("Opened Maps search: \(query)", category: .agent)
        return "Done — Apple Maps is now open and showing results for \"\(query)\". The user can see the results on their screen. Do NOT make up addresses, distances, or specific locations."
    }

    @MainActor
    func openMapsDirections(destination: String) throws -> String {
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        let urlString = "maps://?daddr=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw ToolError.invalidArgument("destination", expected: "valid destination for Maps URL")
        }

        UIApplication.shared.open(url)
        AppLogger.info("Opened Maps directions to: \(destination)", category: .agent)
        return "Done — Apple Maps is now open with directions to \"\(destination)\". The user can see the route on their screen. Do NOT make up addresses or travel times."
    }

    // MARK: - Shortcuts

    @MainActor
    func runShortcut(name: String) throws -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlString = "shortcuts://run-shortcut?name=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw ToolError.invalidArgument("name", expected: "valid shortcut name for URL")
        }

        UIApplication.shared.open(url)
        AppLogger.info("Running shortcut: \(name)", category: .agent)
        return "Done — the shortcut \"\(name)\" has been launched."
    }

    func saveShortcutsToMemory(names: String) throws -> String {
        do {
            try fileSystem.createFile(path: "memory/shortcuts.md", content: "# Saved Shortcuts\n\n\(names)")
            AppLogger.info("Saved shortcut names to memory", category: .agent)
            return "Saved shortcut names to memory. I can reference these when you ask me to run a shortcut."
        } catch {
            throw ToolError.executionFailed("Error saving shortcuts: \(error.localizedDescription)")
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
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count))
        
        // NSDataDetector is good, but if it doesn't specify a time and the user asks for tomorrow,
        // it defaults to 12:00 PM (noon). We will just return its first match.
        return matches?.first?.date
    }
}
