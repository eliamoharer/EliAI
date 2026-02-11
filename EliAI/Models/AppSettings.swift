import Foundation

// MARK: - App Settings

@Observable
class AppSettings {
    // Model
    var selectedModelName: String {
        didSet { save() }
    }
    var maxTokens: Int {
        didSet { save() }
    }
    var temperature: Double {
        didSet { save() }
    }
    var topP: Double {
        didSet { save() }
    }
    var contextLength: Int {
        didSet { save() }
    }

    // UI
    var hapticFeedbackEnabled: Bool {
        didSet { save() }
    }
    var showTimestamps: Bool {
        didSet { save() }
    }

    // Available models
    static let availableModels: [ModelInfo] = [
        ModelInfo(
            name: "HunYuan 0.5B (Q8_0)",
            fileName: "hunyuan-0.5b-instruct-q8_0.gguf",
            downloadURL: "https://huggingface.co/Edge-Quant/Hunyuan-0.5B-Instruct-Q8_0-GGUF/resolve/main/hunyuan-0.5b-instruct-q8_0.gguf",
            sizeBytes: 530_000_000,
            description: "Smallest model, fastest inference. Good for quick responses."
        ),
        ModelInfo(
            name: "HunYuan 1.8B (Q4_K_M)",
            fileName: "hunyuan-1.8b-instruct-q4_k_m.gguf",
            downloadURL: "https://huggingface.co/Edge-Quant/Hunyuan-1.8B-Instruct-Q4_K_M-GGUF/resolve/main/hunyuan-1.8b-instruct-q4_k_m.gguf",
            sizeBytes: 1_100_000_000,
            description: "Larger model, more capable but slower. Better reasoning."
        )
    ]

    init() {
        let defaults = UserDefaults.standard
        self.selectedModelName = defaults.string(forKey: "selectedModelName") ?? "HunYuan 0.5B (Q8_0)"
        self.maxTokens = defaults.integer(forKey: "maxTokens").nonZero ?? 512
        self.temperature = defaults.double(forKey: "temperature").nonZero ?? 0.7
        self.topP = defaults.double(forKey: "topP").nonZero ?? 0.9
        self.contextLength = defaults.integer(forKey: "contextLength").nonZero ?? 2048
        self.hapticFeedbackEnabled = defaults.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
        self.showTimestamps = defaults.object(forKey: "showTimestamps") as? Bool ?? false
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(selectedModelName, forKey: "selectedModelName")
        defaults.set(maxTokens, forKey: "maxTokens")
        defaults.set(temperature, forKey: "temperature")
        defaults.set(topP, forKey: "topP")
        defaults.set(contextLength, forKey: "contextLength")
        defaults.set(hapticFeedbackEnabled, forKey: "hapticFeedbackEnabled")
        defaults.set(showTimestamps, forKey: "showTimestamps")
    }

    var selectedModel: ModelInfo? {
        AppSettings.availableModels.first { $0.name == selectedModelName }
    }
}

// MARK: - Model Info

struct ModelInfo: Identifiable {
    let id = UUID()
    let name: String
    let fileName: String
    let downloadURL: String
    let sizeBytes: Int64
    let description: String

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}

private extension Double {
    var nonZero: Double? {
        self == 0.0 ? nil : self
    }
}
