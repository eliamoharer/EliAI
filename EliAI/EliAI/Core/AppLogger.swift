import Foundation
import os

enum AppLogCategory: String {
    case app
    case model
    case inference
    case agent
    case fileSystem
    case ui
}

struct BreadcrumbEntry: Codable {
    let timestamp: Date
    let category: String
    let level: String
    let message: String
}

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.eliaigemini.localai"

    static func debug(_ message: String, category: AppLogCategory) {
        logger(for: category).debug("\(message, privacy: .public)")
        record(message, category: category, level: "debug")
    }

    static func info(_ message: String, category: AppLogCategory) {
        logger(for: category).info("\(message, privacy: .public)")
        record(message, category: category, level: "info")
    }

    static func warning(_ message: String, category: AppLogCategory) {
        logger(for: category).warning("\(message, privacy: .public)")
        record(message, category: category, level: "warning")
    }

    static func error(_ message: String, category: AppLogCategory) {
        logger(for: category).error("\(message, privacy: .public)")
        record(message, category: category, level: "error")
    }

    static func breadcrumbs() async -> [BreadcrumbEntry] {
        await BreadcrumbStore.shared.snapshot()
    }

    private static func logger(for category: AppLogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    private static func record(_ message: String, category: AppLogCategory, level: String) {
        Task {
            await BreadcrumbStore.shared.add(
                BreadcrumbEntry(timestamp: Date(), category: category.rawValue, level: level, message: message)
            )
        }
    }
}

actor BreadcrumbStore {
    static let shared = BreadcrumbStore()

    private let maxEntries = 200
    private var entries: [BreadcrumbEntry] = []
    private let fileURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = baseURL.appendingPathComponent("eliai_breadcrumbs.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([BreadcrumbEntry].self, from: data) {
            entries = loaded
        }
    }

    func add(_ entry: BreadcrumbEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    func snapshot() -> [BreadcrumbEntry] {
        entries
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
