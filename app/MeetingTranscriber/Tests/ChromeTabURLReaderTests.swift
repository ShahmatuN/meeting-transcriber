#if !APPSTORE
    @testable import MeetingTranscriber
    import XCTest

    /// The parser only. Running `osascript` against a real Chrome needs an
    /// Automation grant the test host does not have, and would launch Chrome
    /// if the running-app guard ever regressed; that path is manual QA.
    final class ChromeTabURLReaderTests: XCTestCase {
        func testOneURLPerLineInOrder() {
            let urls = ChromeTabURLReader.parse(
                "https://mail.google.com/mail/u/0/\nhttps://meet.google.com/abc-defg-hij\n",
            )
            XCTAssertEqual(
                urls.map(\.absoluteString),
                ["https://mail.google.com/mail/u/0/", "https://meet.google.com/abc-defg-hij"],
            )
        }

        func testBlankLinesMissingValuesAndDuplicatesAreDropped() {
            let urls = ChromeTabURLReader.parse(
                "\n  https://a.example/ \nmissing value\nhttps://a.example/\nchrome://newtab/\n\n",
            )
            XCTAssertEqual(urls.map(\.absoluteString), ["https://a.example/", "chrome://newtab/"])
        }

        func testEmptyOutputParsesToNothing() {
            XCTAssertEqual(ChromeTabURLReader.parse(""), [])
        }

        func testTheScriptTalksToChromeAndOnlyChrome() {
            // A `tell application` to anything else would prompt for (and
            // launch) another app; the bundle guard in `tabURLs` is keyed on
            // the same identity.
            XCTAssertTrue(ChromeTabURLReader.script.contains("tell application \"Google Chrome\""))
            XCTAssertEqual(ChromeTabURLReader.bundleIdentifier, "com.google.Chrome")
        }
    }
#endif
