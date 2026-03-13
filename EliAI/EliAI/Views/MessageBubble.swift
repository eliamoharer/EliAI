import Foundation
import SwiftUI
import SwiftMath
import UIKit

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

                if !cachedVisibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    (message.role != .assistant && message.role != .tool) {
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
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundColor(.gray)
            }
        }
        .onAppear { loadContent() }
        .onChange(of: message.content) { _, _ in loadContent() }
    }

    private func loadContent() {
        let parsed = parseThinkingAndTools(from: message.content)
        let visible = (message.role == .assistant || message.role == .tool)
            ? parsed.visible
            : message.content
        
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
            // Keep incomplete blocks visible until closing tag arrives.
            visible += String(scanner[start.lowerBound...])
            scanner = ""
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
             // Keep incomplete blocks visible until closing tag arrives.
             visible += String(scanner[start.lowerBound...])
             scanner = ""
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
            MathDelimiter(open: "\\begin{gather*}", close: "\\end{gather*}", display: true),
            MathDelimiter(open: "\\begin{gather}", close: "\\end{gather}", display: true),
            MathDelimiter(open: "\\begin{aligned}", close: "\\end{aligned}", display: true),
            MathDelimiter(open: "\\begin{array}", close: "\\end{array}", display: true),
            MathDelimiter(open: "\\begin{matrix}", close: "\\end{matrix}", display: true),
            MathDelimiter(open: "\\begin{bmatrix}", close: "\\end{bmatrix}", display: true),
            MathDelimiter(open: "\\begin{pmatrix}", close: "\\end{pmatrix}", display: true),
            MathDelimiter(open: "\\begin{vmatrix}", close: "\\end{vmatrix}", display: true),
            MathDelimiter(open: "\\begin{Vmatrix}", close: "\\end{Vmatrix}", display: true),
            MathDelimiter(open: "\\begin{multline*}", close: "\\end{multline*}", display: true),
            MathDelimiter(open: "\\begin{multline}", close: "\\end{multline}", display: true),
            MathDelimiter(open: "\\begin{cases*}", close: "\\end{cases*}", display: true),
            MathDelimiter(open: "\\begin{cases}", close: "\\end{cases}", display: true),
            MathDelimiter(open: "$$", close: "$$", display: true),
            MathDelimiter(open: "\\[", close: "\\]", display: true),
            MathDelimiter(open: "\\(", close: "\\)", display: false),
            MathDelimiter(open: "$", close: "$", display: false)
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

            let rawLatex = String(text[mathStart..<endRange.lowerBound])
            let latex = rawLatex.trimmingCharacters(in: .whitespacesAndNewlines)

            if !latex.isEmpty {
                if !startMatch.delimiter.display && startMatch.delimiter.open == "$" && !looksLikeInlineMath(latex) {
                    let original = String(text[startMatch.range.lowerBound..<endRange.upperBound])
                    segments.append(MessageSegment(kind: .markdown(original)))
                } else {
                    segments.append(MessageSegment(kind: .math(latex, display: startMatch.delimiter.display)))
                }
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

                if delimiter.open == "$" {
                    if text[range.lowerBound...].hasPrefix("$$") {
                        searchStart = text.index(after: range.lowerBound)
                        continue
                    }
                    if range.lowerBound > text.startIndex {
                        let prev = text[text.index(before: range.lowerBound)]
                        if prev.isNumber {
                            searchStart = range.upperBound
                            continue
                        }
                    }
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

            if delimiter.close == "$" {
                if text[range.lowerBound...].hasPrefix("$$") {
                    searchStart = text.index(after: range.lowerBound)
                    continue
                }
                let content = text[start..<range.lowerBound]
                if content.contains("\n") {
                    return nil
                }
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

    private func looksLikeInlineMath(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"^\d[\d,.]*$"#, options: .regularExpression) != nil { return false }
        if trimmed.contains("\\") { return true }
        if trimmed.contains("^") || trimmed.contains("_") { return true }
        if trimmed.contains("{") && trimmed.contains("}") { return true }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        if words.count > 8 { return false }
        let hasDigits = trimmed.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
        let hasLetters = trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
        if hasLetters && hasDigits { return true }
        if hasLetters && words.count <= 3 && words.allSatisfy({ $0.count <= 5 }) { return true }
        return false
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

private struct MarkdownMathText: UIViewRepresentable {
    let text: String
    let role: ChatMessage.Role
    private static let orderedListRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(\s*)(\d+)\.\s+(.*)$"#)
        } catch {
            AppLogger.error("Failed to compile ordered list regex: \(error)", category: .ui)
            // Return a regex that matches nothing as fallback
            return try! NSRegularExpression(pattern: #"(?!.*)"#)
        }
    }()
    
    private static let unorderedListRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(\s*)[-*+]\s+(.*)$"#)
        } catch {
            AppLogger.error("Failed to compile unordered list regex: \(error)", category: .ui)
            return try! NSRegularExpression(pattern: #"(?!.*)"#)
        }
    }()
    
    private static let headingRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(#{1,6})\s+(.*)$"#)
        } catch {
            AppLogger.error("Failed to compile heading regex: \(error)", category: .ui)
            return try! NSRegularExpression(pattern: #"(?!.*)"#)
        }
    }()

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.font = .systemFont(ofSize: 17)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.dataDetectorTypes = []
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = makeAttributedText()
        uiView.tintColor = .systemBlue
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let proposedWidth = proposal.width ?? UIScreen.main.bounds.width
        let width = proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : UIScreen.main.bounds.width
        let measured = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    private func makeAttributedText() -> NSAttributedString {
        let cleanText = MessageFormatting.normalizeNewlines(text.isEmpty ? " " : text)
        let normalizedMarkdown = MessageFormatting.normalizeMarkdown(cleanText)
        let displayMarkdown = normalizedMarkdown.replacingOccurrences(of: "\\$", with: "$")

        let mutable = buildStructuredAttributedText(from: displayMarkdown)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let textColor: UIColor = role == .user ? .white : .label
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: textColor, range: range)
            }
        }
        if role == .user {
            mutable.addAttribute(.foregroundColor, value: UIColor.white, range: fullRange)
        }

        applyReadableTextSizing(to: mutable, delta: 0)
        return mutable
    }

    private func buildStructuredAttributedText(from markdown: String) -> NSMutableAttributedString {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let output = NSMutableAttributedString()

        for index in lines.indices {
            let line = lines[index]
            output.append(renderStructuredLine(line))
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }
        }

        return output
    }

    private func renderStructuredLine(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return NSAttributedString(string: "")
        }

        if let ordered = parseOrderedListLine(line) {
            return renderListLine(
                prefix: "\(ordered.number). ",
                content: ordered.content,
                indentLevel: ordered.indentLevel
            )
        }

        if let unordered = parseUnorderedListLine(line) {
            return renderListLine(
                prefix: "\u{2022} ",
                content: unordered.content,
                indentLevel: unordered.indentLevel
            )
        }

        if let heading = parseHeadingLine(line) {
            let headingText = inlineAttributedString(from: heading.content)
            let mutable = NSMutableAttributedString(attributedString: headingText)
            applyHeadingStyle(to: mutable, level: heading.level)
            return mutable
        }

        return inlineAttributedString(from: line)
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

    private func renderListLine(prefix: String, content: String, indentLevel: Int) -> NSAttributedString {
        let indentWidth = CGFloat(indentLevel) * 18.0
        let listText = NSMutableAttributedString()
        listText.append(NSAttributedString(string: String(repeating: " ", count: indentLevel * 2)))
        listText.append(NSAttributedString(string: prefix))
        
        // Process content with inline math support - placeholders should be preserved
        // Create attributed string from content (which may contain placeholders)
        let contentAttributed = inlineAttributedString(from: content)
        listText.append(contentAttributed)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = indentWidth
        paragraphStyle.headIndent = indentWidth + 18.0
        paragraphStyle.paragraphSpacing = 2
        listText.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: listText.length)
        )
        return listText
    }

    private func inlineAttributedString(from markdownInline: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: markdownInline, options: options) {
            return NSMutableAttributedString(attributed)
        }
        return NSMutableAttributedString(string: markdownInline)
    }

    private func applyHeadingStyle(to attributed: NSMutableAttributedString, level: Int) {
        let base = UIFont.preferredFont(forTextStyle: .body).pointSize
        let bump: CGFloat
        switch level {
        case 1: bump = 8
        case 2: bump = 6
        case 3: bump = 4
        case 4: bump = 3
        default: bump = 2
        }
        let headingFont = UIFont.systemFont(ofSize: base + bump, weight: .semibold)
        attributed.addAttribute(.font, value: headingFont, range: NSRange(location: 0, length: attributed.length))
    }

    private func applyReadableTextSizing(to mutable: NSMutableAttributedString, delta: CGFloat) {
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else {
            return
        }

        let baseBodyFont = UIFont.preferredFont(forTextStyle: .body)
        var updates: [(NSRange, UIFont)] = []
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if let font = value as? UIFont {
                updates.append((range, font.withSize(font.pointSize + delta)))
            } else {
                updates.append((range, baseBodyFont.withSize(baseBodyFont.pointSize + delta)))
            }
        }

        for (range, font) in updates {
            mutable.addAttribute(.font, value: font, range: range)
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
            let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            let minHeight: CGFloat = labelMode == .display ? 34 : 24
            return CGSize(width: width, height: max(minHeight, size.height))
        }
        return nil
    }
}
