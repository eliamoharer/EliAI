import Foundation
import SwiftUI

private struct MessageSegment {
    enum Kind {
        case markdown(String)
        case math(String, display: Bool)
    }

    let kind: Kind
}

private struct MathDelimiter {
    let open: String
    let close: String
    let display: Bool
}

struct MessageBubble: View {
    let message: ChatMessage
    @State private var isThinkingVisible = false

    var body: some View {
        let parsed = parseThinkingSections(from: message.content)
        let visibleText = message.role == .assistant ? parsed.visible : message.content
        let segments = parseContentSegments(from: visibleText)

        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
            } else {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)
                    .padding(6)
                    .background(Circle().fill(Color.blue.opacity(0.1)))
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .tool {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .font(.caption2)
                        Text("Tool Output")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.orange)
                }

                if message.role == .assistant, !parsed.thinking.isEmpty {
                    DisclosureGroup(isExpanded: $isThinkingVisible) {
                        Text(parsed.thinking)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Text(isThinkingVisible ? "Hide Thinking" : "Show Thinking")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment)
                }
            }

            if message.role != .user {
                Spacer()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.gray)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: MessageSegment) -> some View {
        switch segment.kind {
        case let .markdown(text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(attributedMessageText(from: text))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }

        case let .math(latex, display):
            VStack(alignment: .leading, spacing: 4) {
                if display {
                    Text("Math")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(formatLatexExpression(latex))
                    .font(.system(display ? .body : .callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.blue
        case .assistant:
            return Color(UIColor.secondarySystemBackground)
        case .system:
            return Color.yellow.opacity(0.2)
        case .tool:
            return Color.orange.opacity(0.1)
        }
    }

    var foregroundColor: Color {
        switch message.role {
        case .user:
            return .white
        default:
            return .primary
        }
    }

    private func parseThinkingSections(from text: String) -> (visible: String, thinking: String) {
        var visible = ""
        var thinkingParts: [String] = []
        var cursor = text.startIndex

        while let startRange = text[cursor...].range(of: "<think>") {
            visible += String(text[cursor..<startRange.lowerBound])
            let thinkingStart = startRange.upperBound

            if let endRange = text[thinkingStart...].range(of: "</think>") {
                let section = String(text[thinkingStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !section.isEmpty {
                    thinkingParts.append(section)
                }
                cursor = endRange.upperBound
            } else {
                let section = String(text[thinkingStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !section.isEmpty {
                    thinkingParts.append(section)
                }
                cursor = text.endIndex
                break
            }
        }

        if cursor < text.endIndex {
            visible += String(text[cursor...])
        }

        visible = visible
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let thinking = thinkingParts.joined(separator: "\n\n")
        return (visible, thinking)
    }

    private func parseContentSegments(from text: String) -> [MessageSegment] {
        let delimiters = [
            MathDelimiter(open: "$$", close: "$$", display: true),
            MathDelimiter(open: "\\[", close: "\\]", display: true),
            MathDelimiter(open: "\\(", close: "\\)", display: false),
            MathDelimiter(open: "$", close: "$", display: false)
        ]

        guard !text.isEmpty else {
            return [MessageSegment(kind: .markdown(" "))]
        }

        var segments: [MessageSegment] = []
        var cursor = text.startIndex

        while let startMatch = nextMathStart(in: text, from: cursor, delimiters: delimiters) {
            let leading = String(text[cursor..<startMatch.range.lowerBound])
            if !leading.isEmpty {
                segments.append(MessageSegment(kind: .markdown(leading.replacingOccurrences(of: "\\$", with: "$"))))
            }

            let mathStart = startMatch.range.upperBound
            guard let endRange = nextMathEnd(in: text, from: mathStart, delimiter: startMatch.delimiter) else {
                let remainder = String(text[startMatch.range.lowerBound...])
                if !remainder.isEmpty {
                    segments.append(MessageSegment(kind: .markdown(remainder.replacingOccurrences(of: "\\$", with: "$"))))
                }
                cursor = text.endIndex
                break
            }

            let latex = String(text[mathStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !latex.isEmpty {
                segments.append(MessageSegment(kind: .math(latex, display: startMatch.delimiter.display)))
            }
            cursor = endRange.upperBound
        }

        if cursor < text.endIndex {
            let trailing = String(text[cursor...]).replacingOccurrences(of: "\\$", with: "$")
            if !trailing.isEmpty {
                segments.append(MessageSegment(kind: .markdown(trailing)))
            }
        }

        if segments.isEmpty {
            return [MessageSegment(kind: .markdown(text))]
        }

        return mergeMarkdownSegments(segments)
    }

    private func mergeMarkdownSegments(_ segments: [MessageSegment]) -> [MessageSegment] {
        var merged: [MessageSegment] = []

        for segment in segments {
            switch segment.kind {
            case let .markdown(text):
                if case let .markdown(existing)? = merged.last?.kind {
                    _ = merged.popLast()
                    merged.append(MessageSegment(kind: .markdown(existing + text)))
                } else {
                    merged.append(segment)
                }
            case .math:
                merged.append(segment)
            }
        }

        return merged
    }

    private func nextMathStart(
        in text: String,
        from start: String.Index,
        delimiters: [MathDelimiter]
    ) -> (range: Range<String.Index>, delimiter: MathDelimiter)? {
        var best: (range: Range<String.Index>, delimiter: MathDelimiter)?

        for delimiter in delimiters {
            var searchStart = start
            while searchStart < text.endIndex,
                  let range = text[searchStart...].range(of: delimiter.open) {
                if delimiter.open == "$", text[range.lowerBound...].hasPrefix("$$") {
                    searchStart = text.index(after: range.lowerBound)
                    continue
                }
                if isEscaped(text, at: range.lowerBound) {
                    searchStart = range.upperBound
                    continue
                }

                if let currentBest = best {
                    if range.lowerBound < currentBest.range.lowerBound {
                        best = (range, delimiter)
                    }
                } else {
                    best = (range, delimiter)
                }
                break
            }
        }

        return best
    }

    private func nextMathEnd(
        in text: String,
        from start: String.Index,
        delimiter: MathDelimiter
    ) -> Range<String.Index>? {
        var searchStart = start

        while searchStart < text.endIndex,
              let range = text[searchStart...].range(of: delimiter.close) {
            if delimiter.close == "$", text[range.lowerBound...].hasPrefix("$$") {
                searchStart = text.index(after: range.lowerBound)
                continue
            }
            if isEscaped(text, at: range.lowerBound) {
                searchStart = range.upperBound
                continue
            }
            return range
        }

        return nil
    }

    private func isEscaped(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        var slashCount = 0
        var cursor = text.index(before: index)

        while true {
            if text[cursor] == "\\" {
                slashCount += 1
            } else {
                break
            }

            if cursor == text.startIndex {
                break
            }
            cursor = text.index(before: cursor)
        }

        return slashCount % 2 == 1
    }

    private func attributedMessageText(from text: String) -> AttributedString {
        let normalized = text.isEmpty ? " " : text
        if let attributed = try? AttributedString(markdown: normalized) {
            return attributed
        }
        return AttributedString(normalized)
    }

    private func formatLatexExpression(_ latex: String) -> String {
        var output = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        output = transformLatexFunctions(output)
        output = replaceMathCommands(in: output)
        output = normalizeScripts(in: output)
        output = output
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .replacingOccurrences(of: "{", with: "(")
            .replacingOccurrences(of: "}", with: ")")
            .replacingOccurrences(of: "\\", with: "")
        return collapseWhitespace(in: output)
    }

    private func transformLatexFunctions(_ input: String) -> String {
        var output = ""
        var cursor = input.startIndex

        while cursor < input.endIndex {
            if input[cursor...].hasPrefix("\\frac") {
                var next = input.index(cursor, offsetBy: 5)
                next = skipWhitespace(in: input, from: next)
                if let numerator = parseBracedArgument(in: input, from: next) {
                    var denominatorStart = skipWhitespace(in: input, from: numerator.next)
                    if let denominator = parseBracedArgument(in: input, from: denominatorStart) {
                        output += "(\(transformLatexFunctions(numerator.content)))/(\(transformLatexFunctions(denominator.content)))"
                        cursor = denominator.next
                        continue
                    }
                }
            }

            if input[cursor...].hasPrefix("\\sqrt") {
                var next = input.index(cursor, offsetBy: 5)
                next = skipWhitespace(in: input, from: next)
                if let argument = parseBracedArgument(in: input, from: next) {
                    output += "sqrt(\(transformLatexFunctions(argument.content)))"
                    cursor = argument.next
                    continue
                }
            }

            if input[cursor...].hasPrefix("\\boxed") {
                var next = input.index(cursor, offsetBy: 6)
                next = skipWhitespace(in: input, from: next)
                if let argument = parseBracedArgument(in: input, from: next) {
                    output += "[\(transformLatexFunctions(argument.content))]"
                    cursor = argument.next
                    continue
                }
            }

            if input[cursor...].hasPrefix("\\text") {
                var next = input.index(cursor, offsetBy: 5)
                next = skipWhitespace(in: input, from: next)
                if let argument = parseBracedArgument(in: input, from: next) {
                    output += transformLatexFunctions(argument.content)
                    cursor = argument.next
                    continue
                }
            }

            output.append(input[cursor])
            cursor = input.index(after: cursor)
        }

        return output
    }

    private func parseBracedArgument(in text: String, from start: String.Index) -> (content: String, next: String.Index)? {
        guard start < text.endIndex, text[start] == "{" else {
            return nil
        }

        var depth = 0
        var cursor = start
        let contentStart = text.index(after: start)

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let content = String(text[contentStart..<cursor])
                    let next = text.index(after: cursor)
                    return (content, next)
                }
            }
            cursor = text.index(after: cursor)
        }

        return nil
    }

    private func skipWhitespace(in text: String, from start: String.Index) -> String.Index {
        var cursor = start
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private func replaceMathCommands(in text: String) -> String {
        let replacements: [String: String] = [
            "\\cdot": " * ",
            "\\times": " x ",
            "\\div": " / ",
            "\\pm": " +/- ",
            "\\mp": " -/+ ",
            "\\neq": " != ",
            "\\leq": " <= ",
            "\\geq": " >= ",
            "\\approx": " ~= ",
            "\\to": " -> ",
            "\\rightarrow": " -> ",
            "\\leftarrow": " <- ",
            "\\infty": " infinity ",
            "\\sum": " sum ",
            "\\prod": " prod ",
            "\\int": " integral ",
            "\\alpha": " alpha ",
            "\\beta": " beta ",
            "\\gamma": " gamma ",
            "\\delta": " delta ",
            "\\epsilon": " epsilon ",
            "\\theta": " theta ",
            "\\lambda": " lambda ",
            "\\mu": " mu ",
            "\\pi": " pi ",
            "\\sigma": " sigma ",
            "\\phi": " phi ",
            "\\omega": " omega ",
            "\\sin": " sin ",
            "\\cos": " cos ",
            "\\tan": " tan ",
            "\\log": " log ",
            "\\ln": " ln ",
            "\\,": " ",
            "\\;": " ",
            "\\!": ""
        ]

        var output = text
        for key in replacements.keys.sorted(by: { $0.count > $1.count }) {
            if let value = replacements[key] {
                output = output.replacingOccurrences(of: key, with: value)
            }
        }

        return output
    }

    private func normalizeScripts(in text: String) -> String {
        var output = ""
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "^" || character == "_" {
                let marker = character
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "{", let argument = parseBracedArgument(in: text, from: next) {
                    output.append(marker)
                    output += "(\(argument.content))"
                    cursor = argument.next
                    continue
                }
            }

            output.append(character)
            cursor = text.index(after: cursor)
        }

        return output
    }

    private func collapseWhitespace(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let normalized = lines.map { line in
            line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        return normalized.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
