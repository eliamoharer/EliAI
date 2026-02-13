import Foundation
import SwiftUI
import SwiftMath
import UIKit

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
    let isStreaming: Bool
    @State private var isThinkingVisible = false

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    var body: some View {
        let parsed = parseThinkingSections(from: message.content)
        let visibleText = message.role == .assistant ? parsed.visible : message.content
        let segments = isStreaming
            ? [MessageSegment(kind: .markdown(visibleText))]
            : parseContentSegments(from: visibleText)

        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
            } else {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundColor(.blue)
                    .padding(6)
                    .background(Circle().fill(Color.blue.opacity(0.14)))
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
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

                if !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.role != .assistant {
                    messageContent(segments: segments)
                }
            }

            if message.role != .user {
                Spacer()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundColor(.gray)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            LinearGradient(
                colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .assistant:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        case .system:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.yellow.opacity(0.22))
        case .tool:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.18))
        }
    }

    @ViewBuilder
    private func messageContent(segments: [MessageSegment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.role == .tool {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(.caption2)
                    Text("Tool Output")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.orange)
            }

            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                segmentContent(segment)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundColor(message.role == .user ? .white : .primary)
        .textSelection(.enabled)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(message.role == .user ? 0.22 : 0.25), lineWidth: 0.7)
        )
    }

    @ViewBuilder
    private func segmentContent(_ segment: MessageSegment) -> some View {
        switch segment.kind {
        case let .markdown(text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(attributedMessageText(from: text))
                    .textSelection(.enabled)
            }
        case let .math(latex, display):
            MathSegmentView(latex: latex, display: display, role: message.role)
                .padding(.vertical, display ? 4 : 1)
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
            return promoteStandaloneLatex(in: [MessageSegment(kind: .markdown(text))])
        }

        return promoteStandaloneLatex(in: mergeMarkdownSegments(segments))
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

    private func promoteStandaloneLatex(in segments: [MessageSegment]) -> [MessageSegment] {
        var promoted: [MessageSegment] = []

        for segment in segments {
            switch segment.kind {
            case .math:
                promoted.append(segment)
            case let .markdown(text):
                promoted.append(contentsOf: splitMarkdownIntoLatexAwareSegments(text))
            }
        }

        return mergeMarkdownSegments(promoted)
    }

    private func splitMarkdownIntoLatexAwareSegments(_ text: String) -> [MessageSegment] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [MessageSegment] = []

        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if looksLikeStandaloneLatex(trimmed) {
                result.append(MessageSegment(kind: .math(trimmed, display: true)))
            } else {
                var restored = line
                if index < lines.count - 1 {
                    restored.append("\n")
                }
                if !restored.isEmpty {
                    result.append(MessageSegment(kind: .markdown(restored)))
                }
            }
        }

        return result
    }

    private func looksLikeStandaloneLatex(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let explicitMathCommands = [
            "\\frac", "\\sqrt", "\\sum", "\\int", "\\prod", "\\lim", "\\log", "\\ln",
            "\\left", "\\right", "\\begin{", "\\end{", "\\boxed", "\\overline", "\\underline",
            "\\alpha", "\\beta", "\\gamma", "\\delta", "\\theta", "\\lambda", "\\mu", "\\pi",
            "\\sigma", "\\phi", "\\omega", "\\Delta", "\\partial", "\\nabla", "\\infty",
            "\\times", "\\cdot", "\\pm", "\\mp", "\\leq", "\\geq", "\\neq"
        ]

        if line.hasPrefix("$$"), line.hasSuffix("$$") {
            return true
        }
        if line.hasPrefix("\\["), line.hasSuffix("\\]") {
            return true
        }
        if line.hasPrefix("\\("), line.hasSuffix("\\)") {
            return true
        }

        guard explicitMathCommands.contains(where: { line.contains($0) }) else {
            return false
        }

        // Avoid treating prose with occasional latex command mentions as full equations.
        let plainWordCount = line
            .split(whereSeparator: { $0.isWhitespace })
            .map { token -> String in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "\\{}[]()^_+-=*/,:;.!?\"'`$"))
            }
            .filter { token in
                !token.isEmpty && token.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
            }
            .count

        let hasMathStructure = line.contains("=") || line.contains("^") || line.contains("_")
        return hasMathStructure || plainWordCount <= 2
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
        let normalized = normalizedMarkdown(text.isEmpty ? " " : text)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: normalized, options: options) {
            return attributed
        }
        return AttributedString(normalized)
    }

    private func normalizedMarkdown(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
        value = value.replacingOccurrences(
            of: #"(?<!\n)\s+(#{1,6}\s)"#,
            with: "\n$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?m)^(#{1,6})([^ #])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?<!\n)\s+(\d+\.\s)"#,
            with: "\n$1",
            options: .regularExpression
        )
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        let normalizedLines = lines.map { rawLine -> String in
            let line = String(rawLine)
            return normalizeInlineListSyntax(in: line)
        }

        return normalizedLines.joined(separator: "\n")
    }

    private func normalizeInlineListSyntax(in line: String) -> String {
        var output = line

        if let range = output.range(of: ": - ") {
            let prefix = String(output[..<range.lowerBound]) + ":"
            let listPart = String(output[range.upperBound...])
                .replacingOccurrences(of: " - ", with: "\n- ")
            output = prefix + "\n- " + listPart
        }

        let looksLikeInlineList = output.contains(" - **") ||
            output.contains(" - `") ||
            output.contains(" - [") ||
            output.contains(" - (") ||
            output.trimmingCharacters(in: .whitespaces).hasPrefix("#")

        if looksLikeInlineList {
            output = output.replacingOccurrences(
                of: #"\s+-(?=[A-Za-z])"#,
                with: "\n- ",
                options: .regularExpression
            )
            output = output.replacingOccurrences(
                of: #"\s+-\s+(?=(\*\*|`|\[|\(|[A-Za-z0-9]))"#,
                with: "\n- ",
                options: .regularExpression
            )
        }

        return output
    }
}

private struct MathSegmentView: View {
    let latex: String
    let display: Bool
    let role: ChatMessage.Role

    var body: some View {
        let mathLabel = LaTeXMathLabel(
            equation: latex,
            font: .latinModernFont,
            textAlignment: .left,
            fontSize: display ? 23 : 20,
            labelMode: display ? .display : .text,
            textColor: role == .user ? UIColor.white : UIColor.label,
            insets: MTEdgeInsets(
                top: display ? 4 : 1,
                left: 0,
                bottom: display ? 4 : 1,
                right: 0
            )
        )

        if display {
            ScrollView(.horizontal, showsIndicators: false) {
                mathLabel
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, 2)
            }
            .frame(minHeight: 44)
        } else {
            mathLabel
                .frame(minHeight: 30)
        }
    }
}

private struct LaTeXMathLabel: UIViewRepresentable {
    // Native renderer from SwiftMath; no web assets or network needed at runtime.
    var equation: String
    var font: MathFont = .latinModernFont
    var textAlignment: MTTextAlignment = .left
    var fontSize: CGFloat = 30
    var labelMode: MTMathUILabelMode = .text
    var textColor: MTColor = UIColor.label
    var insets: MTEdgeInsets = MTEdgeInsets()

    func makeUIView(context: Context) -> MTMathUILabel {
        let view = MTMathUILabel()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: MTMathUILabel, context: Context) {
        view.latex = equation
        let selectedFont = MTFontManager().font(withName: font.rawValue, size: fontSize)
        view.font = selectedFont
        view.textAlignment = textAlignment
        view.labelMode = labelMode
        view.textColor = textColor
        view.contentInsets = insets
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        if let width = proposal.width, width.isFinite, width > 0 {
            var measuringBounds = uiView.bounds
            measuringBounds.size.width = width
            uiView.bounds = measuringBounds
            let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let minHeight: CGFloat = labelMode == .display ? 34 : 24
            return CGSize(width: width, height: max(minHeight, size.height))
        }
        return nil
    }
}
