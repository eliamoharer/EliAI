import Foundation
import Observation
import UserNotifications

struct TaskItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var details: String
    var isCompleted: Bool
    var dueDate: Date?
    var notificationID: String?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        notificationID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.notificationID = notificationID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        notificationID = try container.decodeIfPresent(String.self, forKey: .notificationID)
    }
}

@Observable
class TaskManager {
    var tasks: [TaskItem] = []
    private let fileSystem: FileSystemManager
    private let taskFile = "tasks/tasks.json"

    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
        loadTasks()
    }

    // MARK: - Public API

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if granted {
                AppLogger.info("Notification permission granted.", category: .agent)
            } else if let error {
                AppLogger.error("Notification permission error: \(error.localizedDescription)", category: .agent)
            }
        }
    }

    @discardableResult
    func addTask(title: String, details: String = "", dueDate: Date? = nil) -> TaskItem {
        var task = TaskItem(title: title, details: details, dueDate: dueDate)

        if let due = dueDate {
            let notifID = scheduleNotification(title: title, body: details, at: due)
            task.notificationID = notifID
        }

        tasks.append(task)
        saveTasks()
        AppLogger.info("Task created: \(title)", category: .agent)
        return task
    }

    func scheduleReminder(message: String, delayMinutes: Int) -> String {
        let fireDate = Date().addingTimeInterval(TimeInterval(delayMinutes * 60))
        let notifID = scheduleNotification(
            title: "EliAI Reminder",
            body: message,
            at: fireDate
        )

        let task = TaskItem(
            title: "Reminder: \(message)",
            details: "Scheduled for \(formattedDate(fireDate))",
            dueDate: fireDate,
            notificationID: notifID
        )
        tasks.append(task)
        saveTasks()

        AppLogger.info("Reminder scheduled in \(delayMinutes)m: \(message)", category: .agent)
        return "Reminder set for \(formattedDate(fireDate)) (\(delayMinutes) minutes from now)."
    }

    func completeTask(matching query: String) -> String {
        let lower = query.lowercased()

        guard let index = tasks.firstIndex(where: {
            !$0.isCompleted && $0.title.lowercased().contains(lower)
        }) else {
            return "No matching active task found for \"\(query)\"."
        }

        tasks[index].isCompleted = true

        if let notifID = tasks[index].notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [notifID]
            )
        }

        saveTasks()
        AppLogger.info("Task completed: \(tasks[index].title)", category: .agent)
        return "Completed: \(tasks[index].title)"
    }

    func listTasks(includeCompleted: Bool = false) -> String {
        let filtered = includeCompleted ? tasks : tasks.filter { !$0.isCompleted }
        guard !filtered.isEmpty else {
            return "No tasks found."
        }

        return filtered.enumerated().map { index, task in
            let status = task.isCompleted ? "[done]" : "[pending]"
            let due = task.dueDate.map { " (due: \(formattedDate($0)))" } ?? ""
            return "\(index + 1). \(status) \(task.title)\(due)"
        }.joined(separator: "\n")
    }

    func toggleTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted.toggle()

        if tasks[index].isCompleted, let notifID = tasks[index].notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [notifID]
            )
        }

        saveTasks()
    }

    // MARK: - Notifications

    private func scheduleNotification(title: String, body: String, at date: Date) -> String {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.isEmpty ? title : body
        content.sound = .default

        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false
        )

        let id = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.error("Failed to schedule notification: \(error.localizedDescription)", category: .agent)
            }
        }

        return id
    }

    // MARK: - Persistence

    private func loadTasks() {
        do {
            let content = try fileSystem.readFile(path: taskFile)
            if let data = content.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                tasks = try decoder.decode([TaskItem].self, from: data)
            }
        } catch {
            tasks = []
        }
    }

    private func saveTasks() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(tasks)
            if let jsonString = String(data: data, encoding: .utf8) {
                try fileSystem.createFile(path: taskFile, content: jsonString)
            }
        } catch {
            AppLogger.error("Error saving tasks: \(error.localizedDescription)", category: .agent)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
