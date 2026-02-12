import Foundation
import Observation

struct TaskItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    
    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
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
    
    func addTask(title: String, dueDate: Date? = nil) {
        let task = TaskItem(title: title, dueDate: dueDate)
        tasks.append(task)
        saveTasks()
        AppLogger.info("Task created: \(title)", category: .agent)
    }
    
    func toggleTask(_ id: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isCompleted.toggle()
            saveTasks()
        }
    }
    
    private func loadTasks() {
        do {
            let content = try fileSystem.readFile(path: taskFile)
            if let data = content.data(using: .utf8) {
                tasks = try JSONDecoder().decode([TaskItem].self, from: data)
            }
        } catch {
            // File might not exist yet
            tasks = []
        }
    }
    
    private func saveTasks() {
        do {
            let data = try JSONEncoder().encode(tasks)
            if let jsonString = String(data: data, encoding: .utf8) {
                try fileSystem.createFile(path: taskFile, content: jsonString)
            }
        } catch {
            AppLogger.error("Error saving tasks: \(error.localizedDescription)", category: .agent)
        }
    }
}
