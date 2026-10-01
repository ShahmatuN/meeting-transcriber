@testable import MeetingTranscriber
import XCTest

final class MarkdownBlockTests: XCTestCase {
    func testRecognisesTheBlockShapesAProtocolUses() {
        let blocks = MarkdownBlock.parse("""
        # Meeting protocol

        ## Decisions
        - Ship on Friday
          - behind a flag
        * [x] Done item
        1. First
        2) Second
        > quoted line
        ---
        Closing words.
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Meeting protocol"),
            .heading(level: 2, text: "Decisions"),
            .bullet(indent: 0, text: "Ship on Friday"),
            .bullet(indent: 1, text: "behind a flag"),
            .bullet(indent: 0, text: "Done item"),
            .numbered(indent: 0, marker: "1.", text: "First"),
            .numbered(indent: 0, marker: "2)", text: "Second"),
            .quote("quoted line"),
            .rule,
            .paragraph("Closing words."),
        ])
    }

    func testAdjacentLinesJoinIntoOneParagraphUntilABlankLine() {
        let blocks = MarkdownBlock.parse("first line\nsecond line\n\nnext paragraph")

        XCTAssertEqual(blocks, [.paragraph("first line second line"), .paragraph("next paragraph")])
    }

    func testBoldAtLineStartIsNotABullet() {
        XCTAssertEqual(MarkdownBlock.parse("**Owner:** Alice"), [.paragraph("**Owner:** Alice")])
    }

    func testAHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownBlock.parse("#hashtag"), [.paragraph("#hashtag")])
    }

    func testInlineMarkdownIsRenderedAndUnparsableTextFallsBack() {
        XCTAssertEqual(String(MarkdownBlock.inline("**bold** text").characters), "bold text")
        XCTAssertEqual(String(MarkdownBlock.inline("plain [unclosed").characters), "plain [unclosed")
    }
}
