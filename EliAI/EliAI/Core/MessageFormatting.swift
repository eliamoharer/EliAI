import Foundation

enum MessageFormatting {
    static func normalizeNewlines(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
    }

    static func normalizeMarkdown(_ text: String) -> String {
        var value = normalizeNewlines(text)

        // Replace literal \n (backslash + n) with real newlines, but NOT when
        // followed by a letter — that would corrupt LaTeX commands like \nu, \nabla, \neg.
        value = value.replacingOccurrences(
            of: #"\\n(?![a-zA-Z])"#,
            with: "\n",
            options: .regularExpression
        )

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
        // EDITED: Made stricter to avoid matching "+ " inside math equations. Added (?<=^|\n) anchor.
        value = value.replacingOccurrences(
            of: #"(?<=^|\n)\s*([-*+])\s+(?=(\*\*[^*\n]+\*\*|`[^`\n]+`|\[[^\]\n]+\]|[A-Za-z]))"#,
            with: "$1 ",
            options: .regularExpression
        )
        // EDITED: Made strict for numbered lists too.
        value = value.replacingOccurrences(
            of: #"(?<=^|\n)\s+(\d+\.)\s+(?=\S)"#,
            with: "$1 ",
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
