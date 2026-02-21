import Foundation

/// Centralized configuration constants for the application
struct AppConstants {
    /// LLM Engine Configuration
    struct LLMEngine {
        static let maxPromptCharacters = 16_000
        static let maxHistoryMessages = 24
        static let generationTimeoutSeconds: TimeInterval = 60.0
        static let streamHeartbeatIntervalSeconds: TimeInterval = 2.0
        static let maxRecoveryAttempts = 2
    }
    
    /// Agent Loop Configuration
    struct AgentLoop {
        static let maxSteps = 4
        static let recoveryWaitIntervalSeconds: TimeInterval = 0.5
        static let recoveryMaxWaitAttempts = 120
        static let recoveryCooldownSeconds: TimeInterval = 1.0
    }
    
    /// UI Configuration
    struct UI {
        static let scrollStabilizationDelaySeconds: TimeInterval = 0.08
        static let scrollStabilizationAttempts = 2
    }
    
    /// LaTeX Rendering Configuration
    struct LaTeX {
        static let maxInlineMathLength = 120
        static let fallbackImageMinSize: CGFloat = 6.0
        static let fallbackImageMinHeight: CGFloat = 20.0
        static let maxRenderSize: CGFloat = 4096.0
    }
}
