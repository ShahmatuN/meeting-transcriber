@testable import MeetingTranscriber
import XCTest

/// `TranscriptLayout` at the two pure points it acts on: the paragraph merge
/// and the rendering, plus the Meetings-window parser reading the result.
final class TranscriptLayoutTests: XCTestCase {
    private let turns = [
        TimestampedSegment(start: 0, end: 5, text: "one", speaker: "Me"),
        TimestampedSegment(start: 10, end: 15, text: "two", speaker: "Me"), // 5 s pause
        TimestampedSegment(start: 40, end: 45, text: "three", speaker: "Me"), // 25 s pause
        TimestampedSegment(start: 46, end: 50, text: "four", speaker: "Kirill"),
    ]

    func testCompactBreaksASpeakerAtAnyPauseOverTwoSeconds() {
        let merged = DiarizationProcess.mergeConsecutiveSpeakers(turns, gapThreshold: TranscriptLayout.compact.mergeGap)
        XCTAssertEqual(merged.map(\.text), ["one", "two", "three", "four"])
    }

    func testReadableKeepsATurnTogetherAcrossShortPausesOnly() {
        let merged = DiarizationProcess.mergeConsecutiveSpeakers(turns, gapThreshold: TranscriptLayout.readable.mergeGap)
        // The 5 s pause joins, the 25 s pause (a new topic) still breaks.
        XCTAssertEqual(merged.map(\.text), ["one two", "three", "four"])
        XCTAssertEqual(merged.map(\.start), [0, 40, 46])
    }

    func testReadableSeparatesBlocksWithABlankLine() {
        let merged = DiarizationProcess.mergeConsecutiveSpeakers(turns, gapThreshold: TranscriptLayout.readable.mergeGap)
        let text = merged.transcriptText(note: nil, separator: TranscriptLayout.readable.blockSeparator)
        XCTAssertEqual(text, "[00:00] Me: one two\n\n[00:40] Me: three\n\n[00:46] Kirill: four")
    }

    func testCompactIsTheHistoricalShape() {
        let text = turns.transcriptText(note: nil)
        XCTAssertEqual(text, "[00:00] Me: one\n[00:10] Me: two\n[00:40] Me: three\n[00:46] Kirill: four")
        XCTAssertFalse(TranscriptLayout.compact.hasFrontMatter)
        XCTAssertEqual(TranscriptLayout.compact.mergeGap, DiarizationProcess.mergeGapThreshold)
    }

    func testMeetingsWindowParserSkipsTheHeaderAndBlankLines() {
        let text = """
        ---
        title: "Standup"
        speakers:
          "Me": "0:00:10"
        ---

        [00:00] Me: one two

        [00:46] Kirill: four
        """
        let doc = TranscriptDocument.parse(text)
        XCTAssertEqual(doc.turns.map(\.speaker), ["Me", "Kirill"], "header lines must not become turns — got: \(doc.turns)")
        XCTAssertEqual(doc.turns.map(\.text), ["one two", "four"])
    }

    func testEveryLayoutHasALabelForThePicker() {
        for layout in TranscriptLayout.allCases {
            XCTAssertFalse(layout.label.isEmpty)
        }
    }
}
