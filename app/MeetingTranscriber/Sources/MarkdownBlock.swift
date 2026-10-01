import Foundation

/// A protocol's Markdown, split into the block shapes the Meetings window
/// draws. SwiftUI's `Text` renders inline Markdown only (emphasis, code,
/// links), so headings, lists and rules are recognised here line by line and
/// each block's text is handed to `AttributedString(markdown:)` for the inline
/// part. Covers what the protocol prompt produces, not CommonMark.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, marker: String, text: String)
    case quote(String)
    case paragraph(String)
    case rule

    static func parse(_ markdown: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let leading = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = leading / 2

            if line.isEmpty {
                flushParagraph()
            } else if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flushParagraph()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
            } else if line.wholeMatch(of: /(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,}/) != nil {
                flushParagraph()
                blocks.append(.rule)
            } else if let match = line.firstMatch(of: /^[-*+]\s+(?:\[[ xX]\]\s+)?(.*)$/) {
                flushParagraph()
                blocks.append(.bullet(indent: indent, text: String(match.1)))
            } else if let match = line.firstMatch(of: /^(\d{1,3}[.)])\s+(.*)$/) {
                flushParagraph()
                blocks.append(.numbered(indent: indent, marker: String(match.1), text: String(match.2)))
            } else if let match = line.firstMatch(of: /^>\s?(.*)$/) {
                flushParagraph()
                blocks.append(.quote(String(match.1)))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    /// Inline Markdown for one block's text, falling back to the plain string
    /// when it does not parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
