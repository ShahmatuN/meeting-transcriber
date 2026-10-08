@testable import MeetingTranscriber
import XCTest

/// The YAML header of a `.readable` transcript: what it says, how it is
/// quoted, and the three operations the rest of the app performs on it.
final class TranscriptFrontMatterTests: XCTestCase {
    private let utc = TimeZone.gmt

    private func facts() -> TranscriptFrontMatter.Facts {
        TranscriptFrontMatter.Facts(
            title: "Evgeniy - Kirill: sync",
            start: Date(timeIntervalSince1970: 1_790_000_000), // 2026-09-21 14:13:20 UTC
            durationSeconds: 3727,
            appName: "Microsoft Teams",
            participants: ["Kirill \"K\" M.", "Zlata"],
            calendarEventID: "evt-1",
            engine: "Parakeet",
            diarizer: "sortformer",
            speakers: [(name: "Me", seconds: 1872), (name: "Kirill", seconds: 1780)],
        )
    }

    func testRenderWritesEveryFactQuotedAndTheSpeakersByTime() {
        let header = TranscriptFrontMatter.render(facts(), timeZone: utc)
        XCTAssertEqual(header, """
        ---
        title: "Evgeniy - Kirill: sync"
        date: 2026-09-21
        start: "14:13"
        end: "15:15"
        duration: "1:02:07"
        app: "Microsoft Teams"
        participants: ["Kirill \\"K\\" M.", "Zlata"]
        calendar_event: "evt-1"
        engine: "Parakeet"
        diarizer: "sortformer"
        speakers:
          "Me": "0:31:12"
          "Kirill": "0:29:40"
        ---
        """)
    }

    func testRenderLeavesOutWhatIsNotKnown() {
        var facts = facts()
        facts.start = nil
        facts.calendarEventID = nil
        facts.diarizer = nil
        facts.participants = []
        facts.speakers = []
        let header = TranscriptFrontMatter.render(facts, timeZone: utc)
        for absent in ["date:", "start:", "end:", "calendar_event:", "diarizer:", "participants:", "speakers:"] {
            XCTAssertFalse(header.contains(absent), "\(absent) should be omitted — got:\n\(header)")
        }
        XCTAssertTrue(header.contains("duration: \"1:02:07\""), "duration needs no start")
    }

    func testSpeakersSumSpeakingTimeAndSkipSuppressedAndUnlabelled() {
        let segments = [
            TimestampedSegment(start: 0, end: 5, text: "a", speaker: "Me"),
            TimestampedSegment(start: 5, end: 7, text: "b", speaker: "Me"),
            TimestampedSegment(start: 7, end: 10, text: "c", speaker: "Remote", suppressed: true),
            TimestampedSegment(start: 10, end: 12, text: "d"),
        ]
        let speakers = TranscriptFrontMatter.speakers(from: segments)
        XCTAssertEqual(speakers.count, 1)
        XCTAssertEqual(speakers.first?.name, "Me")
        XCTAssertEqual(speakers.first?.seconds ?? 0, 7, accuracy: 0.001)
    }

    func testStripReturnsTheBodyWithoutHeaderOrLeadingBlankLines() {
        let header = TranscriptFrontMatter.render(facts(), timeZone: utc)
        let text = TranscriptFrontMatter.prepend(header, to: "[00:00] Me: hello\n\n[00:05] Kirill: hi")
        XCTAssertEqual(TranscriptFrontMatter.strip(text), "[00:00] Me: hello\n\n[00:05] Kirill: hi")
        XCTAssertTrue(TranscriptFrontMatter.hasFrontMatter(text))
    }

    func testStripLeavesTextWithoutAHeaderAlone() {
        // A transcript that merely opens with a dash-looking note, or no fence
        // closes the header: nothing is cut.
        XCTAssertEqual(TranscriptFrontMatter.strip("[00:00] Me: hello"), "[00:00] Me: hello")
        XCTAssertEqual(TranscriptFrontMatter.strip("---\ntitle: x\n[00:00] Me: hello"), "---\ntitle: x\n[00:00] Me: hello")
        XCTAssertFalse(TranscriptFrontMatter.hasFrontMatter("--- not a fence\n---\n"))
    }

    func testRenameSpeakersTouchesOnlyTheHeaderKeys() {
        let text = """
        ---
        title: "Standup"
        speakers:
          "R_SPEAKER_0": "0:00:12"
          "Me": "0:00:05"
        ---

        [00:00] R_SPEAKER_0: hello R_SPEAKER_0
        """
        let renamed = TranscriptFrontMatter.renameSpeakers(in: text, renames: [("R_SPEAKER_0", "Alice")])
        XCTAssertTrue(renamed.contains("  \"Alice\": \"0:00:12\""), "got:\n\(renamed)")
        XCTAssertFalse(renamed.contains("\"R_SPEAKER_0\""))
        // The body is the body rename's job; this one must not reach into it.
        XCTAssertTrue(renamed.hasSuffix("[00:00] R_SPEAKER_0: hello R_SPEAKER_0"))
    }

    func testRenameSpeakersWithoutAHeaderIsANoOp() {
        let text = "[00:00] SPEAKER_0: hello"
        XCTAssertEqual(TranscriptFrontMatter.renameSpeakers(in: text, renames: [("SPEAKER_0", "Alice")]), text)
    }

    func testClockIsUnpaddedHoursAndPaddedRest() {
        XCTAssertEqual(TranscriptFrontMatter.clock(0), "0:00:00")
        XCTAssertEqual(TranscriptFrontMatter.clock(59.6), "0:01:00")
        XCTAssertEqual(TranscriptFrontMatter.clock(36061), "10:01:01")
    }
}
