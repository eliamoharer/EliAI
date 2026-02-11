import Foundation

// MARK: - File Item

struct FileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let isDirectory: Bool
    var children: [FileItem]?
    let fileSize: Int64?
    let modifiedDate: Date?

    init(
        name: String,
        path: URL,
        isDirectory: Bool,
        children: [FileItem]? = nil,
        fileSize: Int64? = nil,
        modifiedDate: Date? = nil
    ) {
        self.id = path.absoluteString
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.fileSize = fileSize
        self.modifiedDate = modifiedDate
    }

    var isMarkdown: Bool {
        path.pathExtension.lowercased() == "md"
    }

    var isJSON: Bool {
        path.pathExtension.lowercased() == "json"
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        } else if isMarkdown {
            return "doc.text.fill"
        } else if isJSON {
            return "doc.badge.gearshape"
        } else {
            return "doc.fill"
        }
    }

    var formattedSize: String {
        guard let size = fileSize else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var formattedDate: String {
        guard let date = modifiedDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - File Category

enum FileCategory: String, CaseIterable {
    case memory = "memory"
    case tasks = "tasks"
    case notes = "notes"
    case chats = "chats"

    var displayName: String {
        switch self {
        case .memory: return "Memories"
        case .tasks: return "Tasks"
        case .notes: return "Notes"
        case .chats: return "Past Chats"
        }
    }

    var icon: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .tasks: return "checklist"
        case .notes: return "note.text"
        case .chats: return "bubble.left.and.bubble.right.fill"
        }
    }
}
