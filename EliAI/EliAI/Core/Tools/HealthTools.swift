import Foundation

struct LogWaterTool: Tool {
    let name = "log_water"
    let description = "Log water intake in HealthKit"
    let parameters = ["amount_ml"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let amountStr = arguments["amount_ml"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let amount = Double(amountStr) else {
            throw ToolError.invalidArgument("amount_ml", expected: "a number")
        }
        return try await phoneModeManager.logWater(amountML: amount)
    }
}

struct LogSleepTool: Tool {
    let name = "log_sleep"
    let description = "Log sleep data in HealthKit"
    let parameters = ["start_time", "end_time", "quality?"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let start = arguments["start_time"]?.trimmingCharacters(in: .whitespacesAndNewlines), !start.isEmpty else { throw ToolError.missingArgument("start_time") }
        guard let end = arguments["end_time"]?.trimmingCharacters(in: .whitespacesAndNewlines), !end.isEmpty else { throw ToolError.missingArgument("end_time") }
        return try await phoneModeManager.logSleep(startTime: start, endTime: end, quality: arguments["quality"])
    }
}

struct LogCaffeineTool: Tool {
    let name = "log_caffeine"
    let description = "Log caffeine intake in HealthKit"
    let parameters = ["amount_mg?"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        let amountStr = arguments["amount_mg"] ?? "95"
        let amount = Double(amountStr) ?? 95
        return try await phoneModeManager.logCaffeine(amountMG: amount)
    }
}

struct LogStepsTool: Tool {
    let name = "log_steps"
    let description = "Log steps in HealthKit"
    let parameters = ["count"]
    let phoneModeManager: PhoneModeManager

    func execute(arguments: [String: String]) async throws -> String {
        guard let countStr = arguments["count"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let count = Int(countStr) else {
            throw ToolError.invalidArgument("count", expected: "an integer")
        }
        return try await phoneModeManager.logSteps(count: count)
    }
}
