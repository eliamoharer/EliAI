# Comprehensive Improvement Plan for EliAI

This document outlines a prioritized list of improvements, refactorings, and simplifications for the EliAI codebase, ranging from smallest/easiest to largest/most architectural.

---

## 1. Smallest Improvements (Code Cleanup & Minor Bugs)

### 1.1. Eliminate Redundant Managers
- **Issue:** `MemoryManager.swift` exists but is mostly unused. `AgentManager.swift` handles `create_memory`, `recall_memory`, etc., directly via `FileSystemManager`.
- **Action:** Delete `MemoryManager.swift` or refactor `AgentManager` to actually use `MemoryManager` to centralize memory logic.

### 1.2. Regex Caching and Optimization
- **Issue:** In `PhoneModeManager.swift` (`extractTime`) and `AgentManager.swift` (`extractToolCallPayloads`, `extractLooseToolCallPayloads`), `NSRegularExpression` instances are recreated on every function call.
- **Action:** Move these regular expressions to `static let` or pre-compiled properties to avoid regex compilation overhead during generation loops.

### 1.3. Force Unwrapping Safety
- **Issue:** In `PhoneModeManager.swift`, forced unwrapping (`!`) is used extensively when manipulating dates (e.g., `calendar.date(byAdding: ..., to: ...)!`). While Calendar operations rarely fail, edge cases (e.g., daylight saving transitions) could theoretically cause crashes.
- **Action:** Replace forced unwrapping with `if let` or `guard let` and provide fallback dates or graceful error handling.

### 1.4. Standardized Tool Error Handling
- **Issue:** When tool parsing fails (e.g., missing arguments), `AgentManager` returns custom string messages like `"Error: create_file requires 'path' and 'content'."`
- **Action:** Define an `enum ToolError: Error` with standardized descriptions. This makes it easier to track failure rates and consistently format errors for the LLM.

### 1.5. Remove Silenced `Sendable` Warnings
- **Issue:** In `LLMEngine.swift`, custom lock-based classes (`GenerationProgressTracker`, `GenerationResponseTracker`, `StreamTextBuffer`) use `@unchecked Sendable`.
- **Action:** Swift 6 concurrency makes `@unchecked Sendable` a code smell. Convert these classes to `actor`s to provide compiler-guaranteed thread safety without manual `NSLock` boilerplate.

---

## 2. Medium Refactorings (Structural Improvements)

### 2.1. Decouple UI from the Agent Loop
- **Issue:** `ChatView.swift` contains the `runAgentLoop()` method, which handles multi-step tool execution, model recovery, and message appending. This mixes heavy business logic with view rendering.
- **Action:** Move `runAgentLoop()` into `ChatManager` or a dedicated `ChatCoordinator`. The view should only trigger an intent (e.g., `chatManager.sendMessage(...)`) and observe state changes.

### 2.2. Protocol-Oriented Tool Architecture
- **Issue:** `AgentManager.execute(_:)` is a massive `switch` statement that handles over 20 tools. Adding a new tool requires modifying the central switch, adding the tool to the prompt, and handling argument parsing.
- **Action:** Create a `Tool` protocol:
  ```swift
  protocol Tool {
      var name: String { get }
      var description: String { get }
      var requiredArguments: [String] { get }
      func execute(arguments: [String: String]) async throws -> String
  }
  ```
  Register tools dynamically. This allows features to be modularized (e.g., `MemoryTool`, `HealthTool`) and auto-generates the system prompt based on registered tools.

### 2.3. Dynamic System Prompt Generation
- **Issue:** In `LLMEngine.swift`, the `systemPromptForCurrentStyle` method hardcodes the list of tools (e.g., `"Base tools: File: create_file(path...)"`).
- **Action:** Move the tool capability definitions to `AgentManager`. `LLMEngine` should ask `AgentManager` for the tool prompt string so they stay perfectly in sync.

### 2.4. Dependency Injection via `@Environment`
- **Issue:** `ChatView` requires explicit initialization of `chatManager`, `llmEngine`, `agentManager`, and `modelDownloader`.
- **Action:** Push these managers into the SwiftUI `@Environment` or an `@Environment(\.appDependencies)` container. This cleans up View initializers and makes UI testing much easier by injecting mock environments.

---

## 3. Largest Architectural Changes (Major Systems Overhaul)

### 3.1. Robust Tool JSON Parsing (Grammar Enforcement)
- **Issue:** `AgentManager.swift` relies on extremely complex regex and manual bracket-balancing (`extractFirstJSONObject`, `sanitizeJSONString`) to fix broken JSON from the LLM. This is brittle and slow.
- **Action:** 
  1. If the underlying `LLM` library supports it, use **Grammar Enforcement** (e.g., GBNF) or guided JSON generation to force the model to output valid JSON.
  2. Alternatively, use a robust JSON stream parser designed for LLMs (like `PartialJSON` libraries) rather than custom string manipulation.

### 3.2. NLP-Based Date Parsing
- **Issue:** `PhoneModeManager` contains custom, English-specific logic (`parseNaturalDate`) for parsing natural language times ("in 5 minutes", "tomorrow", "next tuesday"). It's hard to maintain and won't scale to other languages.
- **Action:** Replace the custom date extraction with `NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)`. Apple's built-in NLP is highly optimized, handles multiple languages automatically, and drastically reduces code complexity.

### 3.3. Consolidate Task and Reminder Mental Models
- **Issue:** The app currently has parallel systems for `TaskManager` (internal JSON tasks) and EventKit Reminders (`create_reminder`). This confuses the LLM (e.g., "Remind me to..." could trigger either).
- **Action:** Unify the mental model. Either:
  - Deprecate internal tasks and rely entirely on Apple's Reminders app (EventKit).
  - Explicitly merge them behind a single `create_task` tool, where the user can specify if it should sync to Apple Reminders.

### 3.4. State Machine for Model Recovery
- **Issue:** The retry and model recovery logic in `runAgentLoop()` relies on complex nested `if/while` conditions and loop counters. If the model continually outputs empty strings or hallucinated JSON, it loops until it hits `AppConstants.AgentLoop.maxSteps`.
- **Action:** Refactor the generation loop into an asynchronous **State Machine** (e.g., `Idle -> Generating -> ToolExecution -> Recovering -> Error`). This makes the error handling explicit, testable, and prevents edge-case infinite loops where tools and recoveries interplay unexpectedly.