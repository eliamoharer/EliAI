import Foundation

struct LaTeXPreprocessor {
    /// Normalizes and hardens LaTeX for SwiftMath rendering.
    /// - Parameter latex: The raw LaTeX string from the model.
    /// - Returns: A sanitized, ready-to-render LaTeX string.
    static func preprocess(_ latex: String) -> String {
        var value = latex

        value = value.replacingOccurrences(of: "\\dfrac", with: "\\frac")
        value = value.replacingOccurrences(of: "\\tfrac", with: "\\frac")

        // \boxed is poorly supported by SwiftMath; unwrap to the inner expression.
        value = unwrapMathCommand(named: "boxed", in: value)

        // \textit in math mode can cause rendering failures; unwrap it.
        value = unwrapMathCommand(named: "textit", in: value)

        // Strip \displaystyle only when it appears as a standalone prefix
        // (keeps it when part of a larger expression that depends on it).
        value = value.replacingOccurrences(
            of: #"^\\displaystyle\s*"#,
            with: "",
            options: .regularExpression
        )

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapMathCommand(named command: String, in source: String) -> String {
        let needle = "\\\(command)"
        var output = ""
        var cursor = source.startIndex

        while let match = source[cursor...].range(of: needle) {
            output += String(source[cursor..<match.lowerBound])
            var search = match.upperBound
            
            // Skip whitespace after command
            while search < source.endIndex, source[search].isWhitespace {
                search = source.index(after: search)
            }

            // Expect opening brace
            guard search < source.endIndex, source[search] == "{" else {
                output += needle
                cursor = match.upperBound
                continue
            }

            guard let close = matchingClosingBrace(in: source, openingBraceAt: search) else {
                output += String(source[match.lowerBound...])
                cursor = source.endIndex
                break
            }

            let innerStart = source.index(after: search)
            output += String(source[innerStart..<close])
            cursor = source.index(after: close)
        }

        if cursor < source.endIndex {
            output += String(source[cursor...])
        }
        return output
    }

    private static func matchingClosingBrace(in source: String, openingBraceAt openingIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = openingIndex

        while index < source.endIndex {
            let character = source[index]
            if character == "{" && !isEscapedCharacter(in: source, at: index) {
                depth += 1
            } else if character == "}" && !isEscapedCharacter(in: source, at: index) {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func isEscapedCharacter(in source: String, at index: String.Index) -> Bool {
        guard index > source.startIndex else {
            return false
        }

        var slashCount = 0
        var cursor = source.index(before: index)
        while true {
            if source[cursor] == "\\" {
                slashCount += 1
            } else {
                break
            }
            if cursor == source.startIndex {
                break
            }
            cursor = source.index(before: cursor)
        }
        return slashCount % 2 == 1
    }
}
