@testable import MeetingTranscriber
import XCTest

final class TranscriptDocumentTests: XCTestCase {
    func testConsecutiveLinesBySameSpeakerFoldIntoOneTurn() {
        let doc = TranscriptDocument.parse("""
        [00:01] Me: One, two.
        [00:05] Me: Three.
        [00:09] Alice: Hello.
        """)

        XCTAssertEqual(doc.turns.count, 2)
        XCTAssertEqual(doc.turns[0].speaker, "Me")
        XCTAssertEqual(doc.turns[0].timestamp, "00:01", "a turn carries its first segment's timestamp")
        XCTAssertEqual(doc.turns[0].text, "One, two. Three.")
        XCTAssertEqual(doc.turns[1].speaker, "Alice")
        XCTAssertEqual(doc.turns[1].text, "Hello.")
    }

    func testASpeakerReturningAfterAnotherStartsANewTurn() {
        let doc = TranscriptDocument.parse("""
        [00:01] Me: A.
        [00:02] Bob: B.
        [00:03] Me: C.
        """)

        XCTAssertEqual(doc.turns.map(\.speaker), ["Me", "Bob", "Me"])
    }

    func testHourTimestampsAndNonLatinTextParse() {
        let doc = TranscriptDocument.parse("[1:02:03] Евгений: Раз, два, три.")

        XCTAssertEqual(doc.turns.first?.timestamp, "1:02:03")
        XCTAssertEqual(doc.turns.first?.speaker, "Евгений")
        XCTAssertEqual(doc.turns.first?.text, "Раз, два, три.")
    }

    func testTextContainingAColonStaysWithItsSpeaker() {
        let doc = TranscriptDocument.parse("[00:10] Me: the time is 10:30: late")

        XCTAssertEqual(doc.turns.first?.speaker, "Me")
        XCTAssertEqual(doc.turns.first?.text, "the time is 10:30: late")
    }

    func testOtherLinesAreKeptVerbatimAndBlankLinesDropped() {
        let doc = TranscriptDocument.parse("""
        Note: the microphone track was silent.

        [00:01] Remote: Hi.
        """)

        XCTAssertEqual(doc.turns.count, 2)
        XCTAssertNil(doc.turns[0].speaker)
        XCTAssertNil(doc.turns[0].timestamp)
        XCTAssertEqual(doc.turns[0].text, "Note: the microphone track was silent.")
        XCTAssertEqual(doc.turns[1].speaker, "Remote")
    }

    func testTurnIDsAreUniqueAndOrdered() {
        let doc = TranscriptDocument.parse("plain\n[00:01] A: x\n[00:02] B: y")

        XCTAssertEqual(doc.turns.map(\.id), [0, 1, 2])
    }

    func testEmptyTextIsAnEmptyDocument() {
        XCTAssertTrue(TranscriptDocument.parse("").isEmpty)
        XCTAssertTrue(TranscriptDocument.parse("\n  \n").isEmpty)
    }
}
