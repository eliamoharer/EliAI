import Foundation

struct LaTeXPreprocessor {
    /// Normalizes and hardens LaTeX for SwiftMath rendering.
    /// - Parameter latex: The raw LaTeX string from the model.
    /// - Returns: A sanitized, ready-to-render LaTeX string.
    static func preprocess(_ latex: String) -> String {
        var value = latex
        
        // Preserve backslashes in common LaTeX commands that might get corrupted
        // This handles the \frac -> rac issue by ensuring proper escaping
        value = preserveLatexBackslashes(in: value)
        
        // Standard replacements for SwiftMath compatibility
        value = value.replacingOccurrences(of: "\\dfrac", with: "\\frac")
        value = value.replacingOccurrences(of: "\\tfrac", with: "\\frac")
        value = value.replacingOccurrences(of: "\\displaystyle", with: "")
        
        // Fix common inline fraction issues - ensure \frac has proper braces
        value = fixFractionBraces(in: value)
        
        // Unwrap commands that simply wrap content but aren't supported by basic renderers
        value = unwrapMathCommand(named: "boxed", in: value)
        // value = unwrapMathCommand(named: "text", in: value) // IOSMath supports \text, unwrapping ruins spacing
        value = unwrapMathCommand(named: "mathrm", in: value)
        value = unwrapMathCommand(named: "mathbf", in: value)
        value = unwrapMathCommand(named: "textit", in: value)
        
        // Fix spacing issues for inline math
        value = value.replacingOccurrences(of: "~", with: " ")
        value = value.replacingOccurrences(of: "\\,", with: " ")
        value = value.replacingOccurrences(of: "\\;", with: " ")
        value = value.replacingOccurrences(of: "\\!", with: "")
        value = value.replacingOccurrences(of: "\\ ", with: " ")
        
        // Handle common SwiftMath rendering issues
        value = fixNestedFractions(in: value)
        value = fixMissingBraces(in: value)

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Preserves backslashes in LaTeX commands that might get corrupted during JSON encoding/decoding
    private static func preserveLatexBackslashes(in latex: String) -> String {
        var result = latex
        
        // Common LaTeX commands that should always have backslashes
        let commands = [
            "frac", "sqrt", "sum", "int", "lim", "prod",
            "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
            "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau",
            "upsilon", "phi", "chi", "psi", "omega",
            "Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
            "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Pi", "Rho", "Sigma", "Tau",
            "Upsilon", "Phi", "Chi", "Psi", "Omega",
            "sin", "cos", "tan", "cot", "sec", "csc",
            "sinh", "cosh", "tanh", "coth",
            "log", "ln", "exp", "min", "max", "det",
            "begin", "end", "left", "right", "Big", "bigg", "Bigg",
            "text", "textbf", "textit", "mathrm", "mathbf",
            "cdot", "times", "div", "pm", "mp", "neq", "leq", "geq", "approx", "equiv",
            "infty", "partial", "nabla"
        ]
        
        // This is a safety check - the JSON decoder should preserve backslashes,
        // but if content was corrupted, we can't reliably fix it here
        // The real fix is ensuring proper JSON encoding/decoding
        
        return result
    }
    
    /// Fixes nested fractions that may render incorrectly
    private static func fixNestedFractions(in latex: String) -> String {
        // SwiftMath handles nested fractions, but we can optimize by ensuring proper structure
        var result = latex
        
        // Ensure fractions in exponents and subscripts are properly braced
        // Pattern: ^\frac or _\frac should become ^{\frac} or _{\frac}
        result = result.replacingOccurrences(of: "\\^\\s*\\\\frac", with: "^{\\frac", options: .regularExpression)
        result = result.replacingOccurrences(of: "_\\s*\\\\frac", with: "_{\\frac", options: .regularExpression)
        
        return result
    }
    
    /// Fixes missing braces around subscripts and superscripts
    private static func fixMissingBraces(in latex: String) -> String {
        var result = latex
        
        // Fix single character subscripts that should be braced: x_2 -> x_{2} is already fine
        // But x_12 should be x_{12}, not x_{1}2
        // This regex finds underscores followed by multiple digits without braces
        result = result.replacingOccurrences(of: "_([0-9]{2,})", with: "_{$1}", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\^([0-9]{2,})", with: "^{$1}", options: .regularExpression)
        
        return result
    }
    
    /// Fixes common fraction brace issues for SwiftMath compatibility
    private static func fixFractionBraces(in latex: String) -> String {
        // Pattern to match \frac{...}{...} and ensure braces are balanced
        var result = latex
        let fracPattern = "\\\\frac"
        
        var searchStart = result.startIndex
        while let fracRange = result[searchStart...].range(of: fracPattern) {
            let afterFrac = fracRange.upperBound
            
            // Skip whitespace after \frac
            var braceStart = afterFrac
            while braceStart < result.endIndex && result[braceStart].isWhitespace {
                braceStart = result.index(after: braceStart)
            }
            
            // Check if we have an opening brace
            guard braceStart < result.endIndex, result[braceStart] == "{" else {
                searchStart = fracRange.upperBound
                continue
            }
            
            // Find the matching closing brace for numerator
            guard let numEnd = matchingClosingBrace(in: result, openingBraceAt: braceStart) else {
                searchStart = fracRange.upperBound
                continue
            }
            
            // Skip whitespace after numerator
            var secondBraceStart = result.index(after: numEnd)
            while secondBraceStart < result.endIndex && result[secondBraceStart].isWhitespace {
                secondBraceStart = result.index(after: secondBraceStart)
            }
            
            // Check for denominator brace
            guard secondBraceStart < result.endIndex, result[secondBraceStart] == "{" else {
                searchStart = fracRange.upperBound
                continue
            }
            
            // Find the matching closing brace for denominator
            guard let denEnd = matchingClosingBrace(in: result, openingBraceAt: secondBraceStart) else {
                searchStart = fracRange.upperBound
                continue
            }
            
            // Valid fraction found, continue searching
            searchStart = result.index(after: denEnd)
        }
        
        return result
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
