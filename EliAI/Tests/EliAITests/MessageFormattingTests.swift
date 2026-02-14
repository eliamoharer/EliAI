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

    func testNormalizeMarkdownFixesHeadingsAndListMarkers() {
        let input = "Here are examples: - **Flower** - A beautiful flower\n###Step 2"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains(":\n- **Flower**"))
        XCTAssertTrue(normalized.contains("\n### Step 2"))
    }

    func testNormalizeMarkdownPreservesSingleLineBreakAsHardBreak() {
        let input = "Line one\nLine two"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("Line one\\\nLine two"))
    }

    func testNormalizeMarkdownConvertsLiteralEscapedNewline() {
        let input = "Line one\\nLine two"
        let normalized = MessageFormatting.normalizeMarkdown(input)

        XCTAssertTrue(normalized.contains("Line one\\\nLine two"))
    }
}
