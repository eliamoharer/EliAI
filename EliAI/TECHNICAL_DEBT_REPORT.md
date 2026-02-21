# Technical Debt Report - EliAI

Generated: 2026-02-21

This report documents all identified workarounds, fallbacks, and problematic code patterns that should be addressed in future iterations. These items were NOT fixed in the current debug session as requested - they require careful consideration and architectural decisions.

---

## 🔴 Critical Issues (Should Fix Soon)

### 1. Duplicate `reloadCurrentModel()` Function (FIXED)
- **File:** `LLMEngine.swift`
- **Issue:** Same function was defined twice with different signatures
- **Status:** ✅ Fixed - removed duplicate

---

## 🟡 Workarounds & Fallbacks (Review Required)

### MessageBubble.swift

| Location | Issue Type | Description | Recommendation |
|----------|------------|-------------|----------------|
| `renderFallbackInlineTextImage()` | Fallback | Renders LaTeX as plain text when SwiftMath fails | Investigate WHY SwiftMath rendering fails - may be fixable |
| `sanitizeJSONString()` | Workaround | Complex character-by-character escaping for LaTeX in JSON | Consider using a proper JSON library or different tool call format |
| `removeAnyResidualInlineMathPlaceholders()` | Band-aid | Cleanup for when placeholders slip through rendering | Indicates pipeline issue - root cause should be fixed |
| Multiple regex patterns in `parseThinkingAndTools()` | Heuristic | Complex parsing for various tag formats | Consider standardizing tag format or using a proper parser |
| `inlineAttributedString()` failure handling | Fallback | Returns raw string when markdown parsing fails | Investigate common failure cases |

### LLMEngine.swift

| Location | Issue Type | Description | Recommendation |
|----------|------------|-------------|----------------|
| `extractStringResponse()` | Fallback | Uses Mirror reflection to extract string from `Any` type | Fragile - LLM library should provide typed response |
| Heartbeat + Timeout dual mechanism | Redundant | Two separate timeout systems running simultaneously | Consolidate into single, cleaner timeout mechanism |
| `llm.update` callback reset pattern | Workaround | Callback set to empty closure after generation | Could be cleaner with proper callback lifecycle |

### MessageFormatting.swift

| Location | Issue Type | Description | Recommendation |
|----------|------------|-------------|----------------|
| `normalizeMarkdown()` | Workaround | 10+ regex patterns fixing malformed LLM output | Consider if LLM prompt engineering can reduce malformed output |
| `isLikelyInlineMath()` | Heuristic | Guesses if `$...$` content is math vs currency | Could be replaced with smarter detection or explicit markup |
| `looksLikeCurrencyAmount()` | Special Case | Patch to prevent false positives on currency | Part of broader `$` delimiter ambiguity problem |
| `preserveSingleLineBreaks()` | Workaround | Complex logic for line break preservation | Simplify with better markdown understanding |

### ChatView.swift

| Location | Issue Type | Description | Recommendation |
|----------|------------|-------------|----------------|
| `scrollToBottomStabilized()` | Workaround | Multiple scroll attempts to fix timing issues | Investigate root cause of scroll timing problems |
| `waitForModelReady()` polling | Workaround | Polling loop waiting for model state | Use proper async/await state observation |
| `runAgentLoop()` recovery logic | Complex | Multiple recovery attempts for failed generation | Simplify with better error handling architecture |

---

## 🟠 Code Quality Issues

### DRY Violations

1. **System Prompt Duplication** (FIXED)
   - Previously had 6+ variations of same prompt text
   - Now consolidated into single function with conditional sections

2. **Math Placeholder Pattern**
   - `ZZZMATHPLACEHOLDER` pattern used in multiple files
   - Should be centralized as a constant

### Magic Numbers

```swift
// AppConstants.swift - Good (centralized)
static let maxPromptCharacters = 16_000
static let generationTimeoutSeconds: TimeInterval = 60.0

// Scattered in code - Bad
let indentWidth = CGFloat(indentLevel) * 18.0  // MessageBubble.swift
let mathFontSize = max(17, referenceFont.pointSize + 1)  // MessageBubble.swift
```

### Complex Nested Logic

1. **`parseThinkingAndTools()`** in MessageBubble.swift
   - Multiple nested while loops and switch statements
   - Could benefit from parser combinator pattern

2. **`runAgentLoop()`** in ChatView.swift
   - Deep nesting with multiple state variables
   - Could be refactored into state machine

---

## 🔵 Architectural Considerations

### 1. Tool Call Format
Current format uses custom `根基...bundler` tags with JSON. Consider:
- Standard function calling format if LLM supports it
- Or more robust parsing with proper grammar

### 2. Math Rendering Pipeline
Current pipeline:
```
Raw text → Extract math → Replace with placeholders → Normalize markdown → Render → Restore math
```

Consider:
- Direct rendering without placeholder intermediate step
- Or more robust placeholder system that survives transformations

### 3. State Management
Multiple `@Observable` classes with interdependencies:
- `LLMEngine` ↔ `ChatManager` ↔ `AgentManager`
- Consider unifying state or using dependency injection more formally

### 4. Error Recovery Strategy
Current: Multiple ad-hoc recovery mechanisms
- Consider: Centralized error recovery with clear states

---

## Priority Recommendations

### High Priority
1. ✅ Fix duplicate function (DONE)
2. Investigate SwiftMath rendering failures
3. Consolidate timeout mechanisms

### Medium Priority
1. Simplify math placeholder system
2. Improve tool call format robustness
3. Add proper state machine for agent loop

### Low Priority
1. Extract magic numbers to constants
2. Refactor complex nested functions
3. Improve markdown normalization heuristics

---

## Files Modified in This Session

| File | Changes |
|------|---------|
| `LLMEngine.swift` | Removed duplicate function, overhauled system prompts, added state validation |
| `MessageBubble.swift` | Fixed inline math in lists by passing tokens through rendering pipeline |
| `MessageFormatting.swift` | Added math placeholder protection in regex patterns |