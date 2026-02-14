import Foundation

struct InlineMathToken: Equatable {
    let placeholder: String
    let latex: String
}

enum MessageFormatting {
    private struct InlineMathDelimiter {
        let open: String
        let close: String
    }

    private static let inlineDelimiters = [
        InlineMathDelimiter(open: "\\(", close: "\\)"),
        InlineMathDelimiter(open: "$", close: "$")
    ]

    static func normalizeMarkdown(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")

        // Move inline headings onto their own line when models emit "... ### Header".
        value = value.replacingOccurrences(
            of: #"(?<!\n)\s+(#{1,6})(?=\S)"#,
            with: "\n$1 ",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #"(?<!\n)(#{1,6}\s)"#,
            with: "\n$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?m)^(#{1,6})([^ #])"#,
            with: "$1 $2",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #"(?m)^(\s*)-(?!\s|-)(\S)"#,
            with: "$1- $2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?m)^(\s*)(\d+)\.(?!\s)(\S)"#,
            with: "$1$2. $3",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #":\s*-\s+"#,
            with: ":\n- ",
            options: .regularExpression
        )

        // Force jammed inline list markers into real lines.
        value = value.replacingOccurrences(
            of: #"(?<=\S)\s+([-*+])\s+(?=(\*\*[^*\n]+\*\*|`[^`\n]+`|\[[^\]\n]+\]|[A-Za-z]))"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?<=\S)\s+(\d+\.)\s+(?=\S)"#,
            with: "\n$1 ",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #"(?<!\n)(\*\*[^*\n]{2,}\*\*\s*-\s*)"#,
            with: "\n- $1",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #"(?<=\S)\s+-\s+(?=(\*\*[^*\n]{2,}\*\*|`[^`\n]{1,}`|\[[^\]\n]{1,}\]|[A-Z][^\n]{0,48}))"#,
            with: "\n- ",
            options: .regularExpression
        )

        if value.hasPrefix("\n") {
            value.removeFirst()
        }

        value = normalizeListBlockBoundaries(in: value)
        return preserveSingleLineBreaks(in: value)
    }

    static func extractInlineMathPlaceholders(from text: String) -> (markdown: String, tokens: [InlineMathToken]) {
        guard !text.isEmpty else {
            return ("", [])
        }

        var output = ""
        var tokens: [InlineMathToken] = []
        var cursor = text.startIndex
        var counter = 0

        while let match = nextInlineMathStart(in: text, from: cursor) {
            output += String(text[cursor..<match.range.lowerBound])
            let contentStart = match.range.upperBound

            guard let endRange = nextInlineMathEnd(in: text, from: contentStart, delimiter: match.delimiter) else {
                output += String(text[match.range.lowerBound...])
                cursor = text.endIndex
                break
            }

            let rawLatex = String(text[contentStart..<endRange.lowerBound])
            if rawLatex.contains("\n") {
                output += String(text[match.range.lowerBound..<endRange.upperBound])
                cursor = endRange.upperBound
                continue
            }

            let trimmedLatex = rawLatex.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLatex.isEmpty {
                if match.delimiter.open == "$" {
                    output += String(text[match.range])
                    cursor = match.range.upperBound
                } else {
                    output += String(text[match.range.lowerBound..<endRange.upperBound])
                    cursor = endRange.upperBound
                }
                continue
            }

            if !isLikelyInlineMath(trimmedLatex, delimiter: match.delimiter) {
                if match.delimiter.open == "$" {
                    output += String(text[match.range])
                    cursor = match.range.upperBound
                } else {
                    output += String(text[match.range.lowerBound..<endRange.upperBound])
                    cursor = endRange.upperBound
                }
                continue
            }

            let placeholder = "ZZZMATHPLACEHOLDER\(counter)ZZZ"
            counter += 1
            output += placeholder
            tokens.append(InlineMathToken(placeholder: placeholder, latex: trimmedLatex))
            cursor = endRange.upperBound
        }

        if cursor < text.endIndex {
            output += String(text[cursor...])
        }

        return (output, tokens)
    }

    private static func nextInlineMathStart(
        in text: String,
        from start: String.Index
    ) -> (range: Range<String.Index>, delimiter: InlineMathDelimiter)? {
        var best: (range: Range<String.Index>, delimiter: InlineMathDelimiter)?

        for delimiter in inlineDelimiters {
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
                        let previous = text[text.index(before: range.lowerBound)]
                        if previous.isNumber {
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

    private static func nextInlineMathEnd(
        in text: String,
        from start: String.Index,
        delimiter: InlineMathDelimiter
    ) -> Range<String.Index>? {
        var searchStart = start

        while searchStart < text.endIndex,
              let range = text[searchStart...].range(of: delimiter.close) {
            if isEscaped(text, at: range.lowerBound) {
                searchStart = range.upperBound
                continue
            }

            if delimiter.close == "$", text[range.lowerBound...].hasPrefix("$$") {
                searchStart = text.index(after: range.lowerBound)
                continue
            }

            return range
        }

        return nil
    }

    private static func isLikelyInlineMath(_ latex: String, delimiter: InlineMathDelimiter) -> Bool {
        if delimiter.open == "\\(" {
            return true
        }

        let content = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return false
        }
        if content.count > 120 {
            return false
        }
        if looksLikeCurrencyAmount(content) {
            return false
        }
        if content.contains("\\begin{") || content.contains("\\end{") {
            return false
        }

        let hasLatexCommand = content.contains("\\")
        let hasOperators = content.range(of: #"[=+\-*/^_<>]"#, options: .regularExpression) != nil
        let hasBrackets = content.contains("(") || content.contains(")") || content.contains("[") || content.contains("]")
        let hasMathBraces = content.contains("{") || content.contains("}")
        let hasLetters = content.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        let hasDigits = content.range(of: #"\d"#, options: .regularExpression) != nil

        if hasLatexCommand || hasOperators || hasBrackets || hasMathBraces {
            return true
        }

        if hasDigits, !hasLetters {
            return false
        }
        if hasDigits, hasLetters {
            return true
        }

        let words = content
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }

        // Plain $...$ with longer prose is usually text, not math.
        if words.count > 3 {
            return false
        }
        if words.count == 1 {
            return hasLetters
        }
        return false
    }

    private static func preserveSingleLineBreaks(in value: String) -> String {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1 else {
            return value
        }

        var output = ""
        for index in 0 ..< lines.count {
            let line = lines[index]
            output += line

            guard index < lines.count - 1 else {
                continue
            }

            let nextLine = lines[index + 1]
            if line.trimmingCharacters(in: .whitespaces).isEmpty ||
                nextLine.trimmingCharacters(in: .whitespaces).isEmpty ||
                isMarkdownBlockBoundary(currentLine: line, nextLine: nextLine) {
                output += "\n"
            } else {
                output += "  \n"
            }
        }

        return output
    }

    private static func normalizeListBlockBoundaries(in value: String) -> String {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1 else {
            return value
        }

        var output: [String] = []
        var inCodeFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeFence.toggle()
                output.append(line)
                continue
            }

            if inCodeFence {
                output.append(line)
                continue
            }

            let isListItem = isListItemLine(trimmed)
            let isBlank = trimmed.isEmpty

            if isListItem {
                if let previous = output.last,
                   !previous.trimmingCharacters(in: .whitespaces).isEmpty,
                   !isListItemLine(previous.trimmingCharacters(in: .whitespaces)) {
                    output.append("")
                }
                output.append(line)
                continue
            }

            if !isBlank,
               let previous = output.last,
               isListItemLine(previous.trimmingCharacters(in: .whitespaces)) {
                output.append("")
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    private static func isListItemLine(_ trimmedLine: String) -> Bool {
        trimmedLine.range(of: #"^([-*+]|\d+\.)\s+"#, options: .regularExpression) != nil
    }

    private static func isMarkdownBlockBoundary(currentLine: String, nextLine: String) -> Bool {
        let current = currentLine.trimmingCharacters(in: .whitespaces)
        let next = nextLine.trimmingCharacters(in: .whitespaces)

        if current == "```" || next == "```" {
            return true
        }
        if current.hasPrefix(">") || next.hasPrefix(">") {
            return true
        }
        if next.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil {
            return true
        }
        if next.range(of: #"^([-*+])\s"#, options: .regularExpression) != nil {
            return true
        }
        if next.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            return true
        }
        if isHorizontalRule(next) {
            return true
        }
        if current.contains("|") || next.contains("|") {
            return true
        }
        if current.hasPrefix("$$") || next.hasPrefix("$$") {
            return true
        }
        if current.hasPrefix("\\[") || next.hasPrefix("\\[") {
            return true
        }
        if current.hasPrefix("\\begin{") || next.hasPrefix("\\begin{") {
            return true
        }
        return false
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        if line.allSatisfy({ $0 == "-" }) { return true }
        if line.allSatisfy({ $0 == "*" }) { return true }
        if line.allSatisfy({ $0 == "_" }) { return true }
        return false
    }

    private static func looksLikeCurrencyAmount(_ value: String) -> Bool {
        value.range(
            of: #"^\d{1,3}(,\d{3})*(\.\d{1,2})?$|^\d+(\.\d{1,2})?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isEscaped(_ text: String, at index: String.Index) -> Bool {
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
