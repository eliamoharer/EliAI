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
            of: #":\s*-\s+"#,
            with: ":\n- ",
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

        return value
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
                output += String(text[match.range.lowerBound..<endRange.upperBound])
            } else {
                let placeholder = "«MATH_\(counter)»"
                counter += 1
                output += placeholder
                tokens.append(InlineMathToken(placeholder: placeholder, latex: trimmedLatex))
            }

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
