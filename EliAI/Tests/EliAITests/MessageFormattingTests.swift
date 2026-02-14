import XCTest
@testable import EliAI

final class MessageFormattingTests: XCTestCase {
    func testInlineMathExtractionCapturesSingleDollarMath() {
        let input = "The antiderivative of $x^2$ is $\\frac{x^3}{3}$."
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 2)
        XCTAssertEqual(output.tokens[0].latex, "x^2")
        XCTAssertEqual(output.tokens[1].latex, "\\frac{x^3}{3}")
        XCTAssertFalse(output.markdown.contains("$x^2$"))
        XCTAssertFalse(output.markdown.contains("$\\frac{x^3}{3}$"))
    }

    func testInlineMathExtractionKeepsDisplayMathBlocks() {
        let input = "$$\\frac{1}{3}$$ and inline $x$"
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 1)
        XCTAssertEqual(output.tokens[0].latex, "x")
        XCTAssertTrue(output.markdown.contains("$$\\frac{1}{3}$$"))
    }

    func testInlineMathExtractionKeepsEscapedDollarText() {
        let input = "Cost is \\$5 but math is $x+1$."
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 1)
        XCTAssertEqual(output.tokens[0].latex, "x+1")
        XCTAssertTrue(output.markdown.contains("\\$5"))
    }

    func testInlineMathExtractionSkipsCurrencyLikeDollarAmounts() {
        let input = "This costs $5 and tax is $2.99."
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 0)
        XCTAssertEqual(output.markdown, input)
    }

    func testInlineMathExtractionStillFindsMathAfterCurrency() {
        let input = "Price is $5 and solve $x^2$ now."
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 1)
        XCTAssertEqual(output.tokens[0].latex, "x^2")
        XCTAssertTrue(output.markdown.contains("$5"))
    }

    func testInlineMathExtractionHandlesSpacedInlineMath() {
        let input = "Compute $ x^2 + 1 $ quickly."
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 1)
        XCTAssertEqual(output.tokens[0].latex, "x^2 + 1")
        XCTAssertFalse(output.markdown.contains("$ x^2 + 1 $"))
    }

    func testNormalizeAndExtractHandlesNumberedInlineMathSample() {
        let input = """
        1. $ 3x + 5 = 2x + 9 $
        2. $ \\sqrt{16} + 4 = 6 $
        3. $ \\frac{a}{b} \\times c = d $
        """
        let normalized = MessageFormatting.normalizeMarkdown(input)
        XCTAssertTrue(normalized.contains("1. $ 3x + 5 = 2x + 9 $"))
        XCTAssertTrue(normalized.contains("2. $ \\sqrt{16} + 4 = 6 $"))

        let output = MessageFormatting.extractInlineMathPlaceholders(from: normalized)
        XCTAssertEqual(output.tokens.count, 3)
        XCTAssertEqual(output.tokens[0].latex, "3x + 5 = 2x + 9")
        XCTAssertEqual(output.tokens[1].latex, "\\sqrt{16} + 4 = 6")
        XCTAssertEqual(output.tokens[2].latex, "\\frac{a}{b} \\times c = d")
    }

    func testInlineMathExtractionSkipsPlainTextInsideDollars() {
        let input = "Text with $ not actually math words $ should stay text."
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 0)
        XCTAssertEqual(output.markdown, input)
    }

    func testInlineMathExtractionSkipsBeginEndEnvironmentInsideSingleDollars() {
        let input = "$ \\begin{cases}x^2, & x>0 \\\\ 0, & x \\le 0\\end{cases} $"
        let output = MessageFormatting.extractInlineMathPlaceholders(from: input)

        XCTAssertEqual(output.tokens.count, 0)
        XCTAssertEqual(output.markdown, input)
    }

    func testNormalizeMarkdownFixesHeadingsAndListMarkers() {
        let input = "Here are examples: - **Flower** - A beautiful flower\n###Step 2"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains(":\n- **Flower**"))
        XCTAssertTrue(normalized.contains("\n### Step 2"))
    }

    func testNormalizeMarkdownSplitsJammedListItems() {
        let input = "Here are three simple ways: - **Practice gratitude** - **Connect with others**"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("ways:\n- **Practice gratitude**"))
        XCTAssertTrue(normalized.contains("\n- **Connect with others**"))
    }

    func testNormalizeMarkdownPreservesSingleLineBreakAsHardBreak() {
        let input = "Line one\nLine two"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("Line one  \nLine two"))
    }

    func testNormalizeMarkdownConvertsLiteralEscapedNewline() {
        let input = "Line one\\nLine two"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("Line one  \nLine two"))
    }

    func testNormalizeMarkdownPreservesDoubleNewlineParagraphBreak() {
        let input = "Paragraph one\n\nParagraph two"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("Paragraph one\n\nParagraph two"))
    }

    func testNormalizeMarkdownConvertsLegacyHtmlBreakTags() {
        let input = "Line one<br>Line two<br />Line three<br/>Line four"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertFalse(normalized.contains("<br"))
        XCTAssertTrue(normalized.contains("Line one"))
        XCTAssertTrue(normalized.contains("Line four"))
    }

    func testNormalizeMarkdownPreservesInlineMathBulletLinesAndParagraphBreak() {
        let input = "Here:\\n- $ a = 1 $\\n- $ b = 2 $\\n- $ c = 3 $\\n\\nStep 2:"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("Here:\n\n- $ a = 1 $\n- $ b = 2 $\n- $ c = 3 $\n\nStep 2:"))
    }

    func testNormalizeMarkdownDoesNotTurnInlineDashSentenceIntoList() {
        let input = "The cost - $50 - was high."
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertEqual(normalized, input)
    }
}
