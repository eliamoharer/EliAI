import Foundation
import SwiftUI
import SwiftMath
import UIKit

private extension NSAttributedString.Key {
    static let inlineLatexSource = NSAttributedString.Key("EliInlineLatexSource")
}

private enum MathFont: String {
    case latinModernFont = "latinmodern-math"
    case kpMathLightFont = "kpmath-light"
    case kpMathSansFont = "kpmath-sans"
    case xitsFont = "xits-math"
    case terminiFont = "termini-math"
    case texGyreTermesFont = "texgyretermes-math"
}

private struct MessageSegment {
    enum Kind {
        case markdown(String)
        case math(String, display: Bool)
        case code(String, language: String?)
        case rule
        case table(String)
    }

    let kind: Kind
}

private struct MathDelimiter {
    let open: String
    let close: String
    let display: Bool
}

class MathImageCache {
    static let shared = NSCache<NSString, UIImage>()
    
    static func key(for latex: String, color: UIColor, fontSize: CGFloat) -> NSString {
        // Encode color and size to ensure cache correctness
        return "\(latex)|color:\(color.hash)|size:\(fontSize)" as NSString
    }
}


struct ToolCallInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let arguments: String
}

struct ToolOutputInfo: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: Status
    
    enum Status {
        case success
        case error
        case code
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    @State private var isThinkingVisible = false
    
    @State private var cachedSegments: [MessageSegment] = []
    @State private var cachedThinking: String = ""
    @State private var cachedVisibleText: String = ""
    @State private var cachedToolCalls: [ToolCallInfo] = []
    @State private var cachedToolOutputs: [ToolOutputInfo] = []

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
                if message.role == .assistant, !cachedThinking.isEmpty {
                    DisclosureGroup(isExpanded: $isThinkingVisible) {
                        Text(cachedThinking)
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

                if !cachedToolCalls.isEmpty {
                    ForEach(cachedToolCalls) { tool in
                        DisclosureGroup {
                            Text(tool.arguments)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "hammer.fill")
                                    .font(.caption2)
                                Text("Used Tool: \(tool.name)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                }

                if !cachedToolOutputs.isEmpty {
                    ForEach(cachedToolOutputs) { output in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 0) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(output.content)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundColor(output.status == .error ? .red : .primary)
                                        .padding(10)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                            .padding(.top, 4)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: output.status == .error ? "exclamationmark.triangle.fill" : "terminal.fill")
                                    .font(.caption2)
                                Text(output.status == .error ? "Tool Error" : (output.status == .code ? "Generated Code" : "Tool Result"))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(output.status == .error ? .red : .secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(output.status == .error ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                    }
                }

                if !cachedVisibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (message.role != .assistant && message.role != .tool) {
                    messageContent(segments: cachedSegments)
                        .frame(
                            minWidth: message.role == .user ? UIScreen.main.bounds.width * 0.48 : nil,
                            maxWidth: message.role == .user ? UIScreen.main.bounds.width * 0.86 : nil,
                            alignment: message.role == .user ? .trailing : .leading
                        )
                }
            }

            if message.role != .user {
                Spacer()
            }
        }
        .onAppear { loadContent() }
        .onChange(of: message.content) { _, _ in loadContent() }
    }

    private func loadContent() {
        let parsed = parseThinkingAndTools(from: message.content)
        let visible = message.role == .assistant ? parsed.visible : message.content
        
        if visible != cachedVisibleText || parsed.thinking != cachedThinking || parsed.tools != cachedToolCalls || parsed.toolOutputs != cachedToolOutputs {
            self.cachedVisibleText = visible
            self.cachedThinking = parsed.thinking
            self.cachedToolCalls = parsed.tools
            self.cachedToolOutputs = parsed.toolOutputs
            self.cachedSegments = parseContentSegments(from: visible)
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
        .contextMenu {
            let parsed = parseThinkingAndTools(from: message.content)
            let visible = parsed.visible.trimmingCharacters(in: .whitespacesAndNewlines)
            let thinking = parsed.thinking.trimmingCharacters(in: .whitespacesAndNewlines)

            if !visible.isEmpty {
                Button("Copy Answer") {
                    UIPasteboard.general.string = visible
                }
            }

            if !thinking.isEmpty {
                Button("Copy Thinking") {
                    UIPasteboard.general.string = thinking
                }
            }

            Button("Copy Raw Source") {
                UIPasteboard.general.string = message.content
            }
        }
    }

    @ViewBuilder
    private func segmentContent(_ segment: MessageSegment) -> some View {
        switch segment.kind {
        case let .markdown(text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownMathText(text: text, role: message.role)
            }
        case let .math(latex, display):
            MathSegmentView(latex: latex, display: display, role: message.role)
                .padding(.vertical, display ? 4 : 1)
        case let .code(code, language):
            codeBlockView(code: code, language: language)
        case .rule:
            Rectangle()
                .fill(Color.primary.opacity(message.role == .user ? 0.35 : 0.18))
                .frame(height: 1)
                .padding(.vertical, 4)
        case let .table(tableText):
            tableBlockView(text: tableText)
        }
    }

    @ViewBuilder
    private func codeBlockView(code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption2)
                    .foregroundColor(message.role == .user ? Color.white.opacity(0.85) : .secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.role == .user ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
        )
    }

    @ViewBuilder
    private func tableBlockView(text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.role == .user ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
        )
    }

    private func parseThinkingAndTools(from text: String) -> (visible: String, thinking: String, tools: [ToolCallInfo], toolOutputs: [ToolOutputInfo]) {
        var visible = ""
        var thinkingParts: [String] = []
        var tools: [ToolCallInfo] = []
        var toolOutputs: [ToolOutputInfo] = []
        var scanner = text
        
        // Iterative extraction of "next special block"
        // We look for the earliest occurrence of any tag
        while true {
            let tags = ["<think>", "<tool_call>", "<tool_output>", "<tool_code>", "<tool_result>"]
            var earliestRange: Range<String.Index>?
            var earliestTag: String?
            
            for tag in tags {
                if let range = scanner.range(of: tag) {
                    if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
                        earliestRange = range
                        earliestTag = tag
                    }
                }
            }
            
            guard let range = earliestRange, let tag = earliestTag else {
                break
            }
            
            switch tag {
            case "<think>":
                processThink(in: &scanner, start: range, visible: &visible, thinkingParts: &thinkingParts)
            case "<tool_call>":
                processTool(in: &scanner, start: range, visible: &visible, tools: &tools)
            case "<tool_output>":
                processToolOutput(in: &scanner, start: range, endTag: "</tool_output>", status: .success, visible: &visible, outputs: &toolOutputs)
            case "<tool_result>":
                // Treat tool_result same as tool_output for now
                processToolOutput(in: &scanner, start: range, endTag: "</tool_result>", status: .success, visible: &visible, outputs: &toolOutputs)
            case "<tool_code>":
                processToolOutput(in: &scanner, start: range, endTag: "</tool_code>", status: .code, visible: &visible, outputs: &toolOutputs)
            default:
                break
            }
        }
        
        visible += scanner // Append anything left
        
        let thinking = thinkingParts.joined(separator: "\n\n")
        return (visible.trimmingCharacters(in: .whitespacesAndNewlines), thinking, tools, toolOutputs)
    }

    private func processToolOutput(
        in scanner: inout String,
        start: Range<String.Index>,
        endTag: String,
        status: ToolOutputInfo.Status,
        visible: inout String,
        outputs: inout [ToolOutputInfo]
    ) {
        visible += String(scanner[..<start.lowerBound])
        let contentStart = start.upperBound
        if let endRange = scanner[contentStart...].range(of: endTag) {
            let content = String(scanner[contentStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                 outputs.append(ToolOutputInfo(content: content, status: status))
            }
            scanner = String(scanner[endRange.upperBound...])
        } else {
            // Unclosed, just hide header
            scanner = String(scanner[contentStart...])
        }
    }



    private func processThink(in scanner: inout String, start: Range<String.Index>, visible: inout String, thinkingParts: inout [String]) {
        visible += String(scanner[..<start.lowerBound])
        let contentStart = start.upperBound
        if let endRange = scanner[contentStart...].range(of: "</think>") {
            let content = String(scanner[contentStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { thinkingParts.append(content) }
            scanner = String(scanner[endRange.upperBound...])
        } else {
            // Unclosed
            let content = String(scanner[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { thinkingParts.append(content) }
            scanner = ""
        }
    }

    private func processTool(in scanner: inout String, start: Range<String.Index>, visible: inout String, tools: inout [ToolCallInfo]) {
        visible += String(scanner[..<start.lowerBound])
        let contentStart = start.upperBound
        if let endRange = scanner[contentStart...].range(of: "</tool_call>") {
            let jsonString = String(scanner[contentStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Properly sanitize JSON by escaping backslashes in string values
            // This handles LaTeX commands and other backslash sequences correctly
            let sanitized = sanitizeJSONString(jsonString)

            if let data = sanitized.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String {
                
                // Pretty print arguments
                let prettyArgs = (try? String(data: JSONSerialization.data(withJSONObject: json["arguments"] ?? [:], options: .prettyPrinted), encoding: .utf8)) ?? "{}"
                tools.append(ToolCallInfo(name: name, arguments: prettyArgs))
            } 
            scanner = String(scanner[endRange.upperBound...])
        } else {
             // Unclosed, just hide header
             scanner = String(scanner[contentStart...])
        }
    }
    
    /// Sanitizes JSON string by properly escaping backslashes in string values
    /// This handles LaTeX commands and other backslash sequences that JSON requires to be escaped
    private func sanitizeJSONString(_ jsonString: String) -> String {
        // First, try parsing as-is - if it works, no sanitization needed
        if let _ = try? JSONSerialization.jsonObject(with: jsonString.data(using: .utf8) ?? Data()) {
            return jsonString
        }
        
        // If parsing fails, escape backslashes in string values that aren't part of valid JSON escape sequences
        // Valid JSON escape sequences: ", \, /, b, f, n, r, t, u followed by hex digits
        var result = ""
        var inString = false
        var escapeNext = false
        var i = jsonString.startIndex
        
        while i < jsonString.endIndex {
            let char = jsonString[i]
            
            if escapeNext {
                // We're processing an escape sequence
                if inString {
                    // Check if this is a valid JSON escape sequence
                    let validEscapes = "\"\\/bfnrtu"
                    if validEscapes.contains(char) {
                        result.append("\\")
                        result.append(char)
                    } else {
                        // Not a valid escape - double-escape the backslash
                        result.append("\\\\")
                        result.append(char)
                    }
                } else {
                    result.append("\\")
                    result.append(char)
                }
                escapeNext = false
            } else if char == "\\" {
                if inString {
                    // Check next character to see if it's a valid escape
                    let nextIndex = jsonString.index(after: i)
                    if nextIndex < jsonString.endIndex {
                        let nextChar = jsonString[nextIndex]
                        let validEscapes = "\"\\/bfnrtu"
                        if validEscapes.contains(nextChar) {
                            // Valid escape sequence - keep as-is
                            result.append(char)
                            escapeNext = true
                        } else {
                            // Invalid escape (likely LaTeX) - escape the backslash
                            result.append("\\\\")
                        }
                    } else {
                        // Backslash at end - escape it
                        result.append("\\\\")
                    }
                } else {
                    result.append(char)
                    escapeNext = true
                }
            } else {
                if char == "\"" {
                    inString.toggle()
                }
                result.append(char)
            }
            
            i = jsonString.index(after: i)
        }
        
        return result
    }

    private func parseContentSegments(from text: String) -> [MessageSegment] {
        guard !text.isEmpty else {
            return [MessageSegment(kind: .markdown(" "))]
        }

        let codeAwareSegments = parseCodeFenceAwareSegments(text)
        var parsedSegments: [MessageSegment] = []

        for segment in codeAwareSegments {
            switch segment.kind {
            case let .markdown(markdownChunk):
                parsedSegments.append(contentsOf: parseMathSegments(from: markdownChunk))
            default:
                parsedSegments.append(segment)
            }
        }

        if parsedSegments.isEmpty {
            parsedSegments = [MessageSegment(kind: .markdown(text))]
        }

        return splitMarkdownForRulesAndTables(in: mergeMarkdownSegments(parsedSegments))
    }

    private func parseCodeFenceAwareSegments(_ text: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var cursor = text.startIndex

        while let openRange = text[cursor...].range(of: "```") {
            let leading = String(text[cursor..<openRange.lowerBound])
            if !leading.isEmpty {
                segments.append(MessageSegment(kind: .markdown(leading)))
            }

            let payloadStart = openRange.upperBound
            guard let closeRange = text[payloadStart...].range(of: "```") else {
                let remainder = String(text[openRange.lowerBound...])
                if !remainder.isEmpty {
                    segments.append(MessageSegment(kind: .markdown(remainder)))
                }
                cursor = text.endIndex
                break
            }

            let rawPayload = String(text[payloadStart..<closeRange.lowerBound])
            let payload = parseCodeFencePayload(rawPayload)
            segments.append(MessageSegment(kind: .code(payload.code, language: payload.language)))
            cursor = closeRange.upperBound
        }

        if cursor < text.endIndex {
            let trailing = String(text[cursor...])
            if !trailing.isEmpty {
                segments.append(MessageSegment(kind: .markdown(trailing)))
            }
        }

        return segments.isEmpty ? [MessageSegment(kind: .markdown(text))] : segments
    }

    private func parseCodeFencePayload(_ rawPayload: String) -> (language: String?, code: String) {
        var payload = rawPayload
        if payload.hasPrefix("\n") {
            payload.removeFirst()
        }

        var language: String?
        if let newlineIndex = payload.firstIndex(of: "\n") {
            let firstLine = String(payload[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if firstLine.range(of: #"^[A-Za-z0-9_+\-#.]+$"#, options: .regularExpression) != nil {
                language = firstLine.lowercased()
                payload = String(payload[payload.index(after: newlineIndex)...])
            }
        }

        while payload.hasSuffix("\n") {
            payload.removeLast()
        }

        return (language, payload)
    }

    private func parseMathSegments(from text: String) -> [MessageSegment] {
        let delimiters = [
            MathDelimiter(open: "\\begin{equation*}", close: "\\end{equation*}", display: true),
            MathDelimiter(open: "\\begin{equation}", close: "\\end{equation}", display: true),
            MathDelimiter(open: "\\begin{align*}", close: "\\end{align*}", display: true),
            MathDelimiter(open: "\\begin{align}", close: "\\end{align}", display: true),
            MathDelimiter(open: "\\begin{multline*}", close: "\\end{multline*}", display: true),
            MathDelimiter(open: "\\begin{multline}", close: "\\end{multline}", display: true),
            MathDelimiter(open: "\\begin{cases*}", close: "\\end{cases*}", display: true),
            MathDelimiter(open: "\\begin{cases}", close: "\\end{cases}", display: true),
            MathDelimiter(open: "$$", close: "$$", display: true),
            MathDelimiter(open: "\\[", close: "\\]", display: true)
        ]

        var segments: [MessageSegment] = []
        var cursor = text.startIndex

        while let startMatch = nextMathStart(in: text, from: cursor, delimiters: delimiters) {
            let leading = String(text[cursor..<startMatch.range.lowerBound])
            if !leading.isEmpty {
                segments.append(MessageSegment(kind: .markdown(leading)))
            }

            let mathStart = startMatch.range.upperBound
            guard let endRange = nextMathEnd(in: text, from: mathStart, delimiter: startMatch.delimiter) else {
                let remainder = String(text[startMatch.range.lowerBound...])
                if !remainder.isEmpty {
                    segments.append(MessageSegment(kind: .markdown(remainder)))
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
            let trailing = String(text[cursor...])
            if !trailing.isEmpty {
                segments.append(MessageSegment(kind: .markdown(trailing)))
            }
        }

        return segments.isEmpty ? [MessageSegment(kind: .markdown(text))] : segments
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
            default:
                merged.append(segment)
            }
        }

        return merged
    }

    private func splitMarkdownForRulesAndTables(in segments: [MessageSegment]) -> [MessageSegment] {
        var splitSegments: [MessageSegment] = []

        for segment in segments {
            switch segment.kind {
            case let .markdown(text):
                splitSegments.append(contentsOf: splitMarkdownChunkForRulesAndTables(text))
            default:
                splitSegments.append(segment)
            }
        }

        return mergeMarkdownSegments(splitSegments)
    }

    private func splitMarkdownChunkForRulesAndTables(_ text: String) -> [MessageSegment] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [MessageSegment] = []
        var markdownBuffer: [String] = []
        var index = 0

        func flushMarkdownBuffer() {
            guard !markdownBuffer.isEmpty else { return }
            result.append(MessageSegment(kind: .markdown(markdownBuffer.joined(separator: "\n"))))
            markdownBuffer.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = String(lines[index])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if isHorizontalRule(trimmed) {
                flushMarkdownBuffer()
                result.append(MessageSegment(kind: .rule))
                index += 1
                continue
            }

            if index + 1 < lines.count,
               looksLikeTableHeader(line),
               looksLikeTableDivider(String(lines[index + 1])) {
                flushMarkdownBuffer()
                var tableLines: [String] = [line, String(lines[index + 1])]
                index += 2

                while index < lines.count {
                    let candidate = String(lines[index])
                    let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.contains("|"), !trimmedCandidate.isEmpty {
                        tableLines.append(candidate)
                        index += 1
                    } else {
                        break
                    }
                }

                result.append(MessageSegment(kind: .table(tableLines.joined(separator: "\n"))))
                continue
            }

            markdownBuffer.append(line)
            index += 1
        }

        flushMarkdownBuffer()
        return result
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        if trimmed.allSatisfy({ $0 == "-" }) { return true }
        if trimmed.allSatisfy({ $0 == "*" }) { return true }
        if trimmed.allSatisfy({ $0 == "_" }) { return true }
        return false
    }

    private func looksLikeTableHeader(_ line: String) -> Bool {
        line.contains("|") && line.split(separator: "|").count >= 3
    }

    private func looksLikeTableDivider(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#, options: .regularExpression) != nil
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

}

private struct MathSegmentView: View {
    let latex: String
    let display: Bool
    let role: ChatMessage.Role

    var body: some View {
        let preparedLatex = LaTeXPreprocessor.preprocess(latex)
        let mathLabel = LaTeXMathLabel(
            equation: preparedLatex,
            font: .latinModernFont,
            textAlignment: .left,
            fontSize: display ? 19 : 18,
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
            .contextMenu {
                Button("Copy LaTeX") {
                    UIPasteboard.general.string = "$$\(latex)$$"
                }
            }
        } else {
            mathLabel
                .frame(minHeight: 30)
                .contextMenu {
                    Button("Copy LaTeX") {
                        UIPasteboard.general.string = "$\(latex)$"
                    }
                }
        }
    }
}

private struct MarkdownMathText: View {
    let text: String
    let role: ChatMessage.Role
    
    var body: some View {
        let cleanText = MessageFormatting.normalizeNewlines(text.isEmpty ? " " : text)
        let extracted = MessageFormatting.extractInlineMathPlaceholders(from: cleanText)
        let normalizedMarkdown = MessageFormatting.normalizeMarkdown(extracted.markdown)
        
        let lines = normalizedMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                LineView(line: line, tokens: extracted.tokens, role: role)
            }
        }
    }
}

private struct InlineMathChunk: Identifiable {
    let id = UUID()
    let isMath: Bool
    let text: String
    let token: InlineMathToken?
}

private struct LineView: View {
    let line: String
    let tokens: [InlineMathToken]
    let role: ChatMessage.Role
    
    private static let orderedListRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^(\s*)(\d+)\.\s+(.*)$"#)
    }()
    
    private static let unorderedListRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^(\s*)[-*+]\s+(.*)$"#)
    }()
    
    private static let headingRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.*)$"#)
    }()

    var body: some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Text(" ")
        } else if let ordered = parseOrderedListLine(line) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(ordered.number).")
                    .frame(width: 24, alignment: .trailing)
                buildConcatenatedText(from: ordered.content)
            }
            .padding(.leading, CGFloat(ordered.indentLevel) * 18.0)
        } else if let unordered = parseUnorderedListLine(line) {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .frame(width: 16, alignment: .center)
                buildConcatenatedText(from: unordered.content)
            }
            .padding(.leading, CGFloat(unordered.indentLevel) * 18.0)
        } else if let heading = parseHeadingLine(line) {
            buildConcatenatedText(from: heading.content)
                .font(headingFont(for: heading.level))
        } else {
            buildConcatenatedText(from: line)
        }
    }
    
    private func buildConcatenatedText(from content: String) -> Text {
        let chunks = splitIntoChunks(content: content)
        return chunks.reduce(Text("")) { result, chunk in
            if chunk.isMath, let token = chunk.token {
                let color = role == .user ? UIColor.white : UIColor.label
                if let img = renderInlineMathImage(latex: token.latex, color: color, fontSize: 17) {
                    let capHeight = UIFont.preferredFont(forTextStyle: .body).capHeight
                    let offset = (capHeight - img.size.height) / 2.0
                    return result + Text(Image(uiImage: img)).baselineOffset(offset)
                } else {
                    return result + Text("$\(token.latex)$")
                }
            } else {
                let options = AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
                let attr = (try? AttributedString(markdown: chunk.text, options: options)) ?? AttributedString(chunk.text)
                return result + Text(attr)
            }
        }
    }
    
    private func splitIntoChunks(content: String) -> [InlineMathChunk] {
        var result: [InlineMathChunk] = []
        var remaining = content
        
        while let nextMatch = nextPlaceholder(in: remaining) {
            let leading = String(remaining[..<nextMatch.range.lowerBound])
            if !leading.isEmpty {
                result.append(InlineMathChunk(isMath: false, text: leading, token: nil))
            }
            
            let idString = String(remaining[nextMatch.range])
            if let token = tokens.first(where: { $0.placeholder == idString }) {
                result.append(InlineMathChunk(isMath: true, text: "", token: token))
            } else {
                result.append(InlineMathChunk(isMath: false, text: idString, token: nil))
            }
            
            remaining = String(remaining[nextMatch.range.upperBound...])
        }
        
        if !remaining.isEmpty {
            result.append(InlineMathChunk(isMath: false, text: remaining, token: nil))
        }
        
        return result
    }
    
    private func nextPlaceholder(in text: String) -> (range: Range<String.Index>, id: String)? {
        if let range = text.range(of: #"ZZZMATHPLACEHOLDER\d+ZZZ"#, options: .regularExpression) {
            return (range, String(text[range]))
        }
        return nil
    }
    
    private func parseOrderedListLine(_ line: String) -> (number: String, content: String, indentLevel: Int)? {
        let regex = Self.orderedListRegex
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              match.numberOfRanges == 4,
              let indentRange = Range(match.range(at: 1), in: line),
              let numberRange = Range(match.range(at: 2), in: line),
              let contentRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        let indentLevel = max(0, line[indentRange].count / 2)
        return (String(line[numberRange]), String(line[contentRange]), indentLevel)
    }

    private func parseUnorderedListLine(_ line: String) -> (content: String, indentLevel: Int)? {
        let regex = Self.unorderedListRegex
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              match.numberOfRanges == 3,
              let indentRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let indentLevel = max(0, line[indentRange].count / 2)
        return (String(line[contentRange]), indentLevel)
    }

    private func parseHeadingLine(_ line: String) -> (level: Int, content: String)? {
        let regex = Self.headingRegex
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              match.numberOfRanges == 3,
              let levelRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (line[levelRange].count, String(line[contentRange]))
    }
    
    private func headingFont(for level: Int) -> Font {
        let base: CGFloat = 17
        let bump: CGFloat
        switch level {
        case 1: bump = 8
        case 2: bump = 6
        case 3: bump = 4
        case 4: bump = 3
        default: bump = 2
        }
        return Font.system(size: base + bump, weight: .semibold)
    }
    
    private func renderInlineMathImage(latex: String, color: UIColor, fontSize: CGFloat) -> UIImage? {
        let cacheKey = MathImageCache.key(for: latex, color: color, fontSize: fontSize)
        if let cached = MathImageCache.shared.object(forKey: cacheKey) {
            return cached
        }
        
        let label = MTMathUILabel()
        label.backgroundColor = .clear
        label.latex = LaTeXPreprocessor.preprocess(latex)
        label.font = MTFontManager().font(withName: MathFont.latinModernFont.rawValue, size: fontSize)
        label.labelMode = usesDisplayMathLayout(latex) ? .display : .text
        label.textColor = color
        label.textAlignment = .left
        label.contentInsets = MTEdgeInsets(top: 1, left: 0, bottom: 1, right: 0)

        let measured = label.sizeThatFits(
            CGSize(
                width: AppConstants.LaTeX.maxRenderSize,
                height: AppConstants.LaTeX.maxRenderSize
            )
        )
        
        if !measured.width.isFinite || !measured.height.isFinite || measured.width == 0 || measured.height == 0 {
            return nil
        }
        
        let width = max(AppConstants.LaTeX.fallbackImageMinSize, ceil(measured.width))
        let height = max(ceil(fontSize * 1.2), ceil(measured.height))
        let renderSize = CGSize(width: width, height: height)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)

        let image = renderer.image { context in
            label.frame = CGRect(
                x: 0,
                y: max(0, (renderSize.height - measured.height) / 2),
                width: width,
                height: measured.height
            )
            label.setNeedsLayout()
            label.layoutIfNeeded()
            label.layer.render(in: context.cgContext)
        }
        
        MathImageCache.shared.setObject(image, forKey: cacheKey)
        return image
    }

    private func usesDisplayMathLayout(_ latex: String) -> Bool {
        let normalized = latex.replacingOccurrences(of: " ", with: "")
        if normalized.contains("\\begin{cases}") || normalized.contains("\\begin{cases*}") {
            return true
        }
        if normalized.contains("\\begin{aligned}") || normalized.contains("\\begin{matrix}") {
            return true
        }
        if normalized.contains("\\\\") {
            return true
        }
        return false
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
            let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            let minHeight: CGFloat = labelMode == .display ? 34 : 24
            return CGSize(width: width, height: max(minHeight, size.height))
        }
        return nil
    }
}
