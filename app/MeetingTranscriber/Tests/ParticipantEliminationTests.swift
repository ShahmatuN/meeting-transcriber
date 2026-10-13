@testable import MeetingTranscriber
import XCTest

final class ParticipantEliminationTests: XCTestCase {
    private func resolve(
        _ mapping: [String: String],
        times: [String: TimeInterval],
        participants: [String],
        dual: Bool = true,
    ) -> ParticipantElimination.Resolution? {
        ParticipantElimination.resolve(
            mapping: mapping, speakingTimes: times, participants: participants, isDualSource: dual,
        )
    }

    /// A 1-1: the microphone is pinned, the far end is one long voice.
    func testOneToOneNamesAndLearnsTheFarEnd() {
        let result = resolve(
            ["M_S1": "Me", "R_S1": "R_S1"],
            times: ["M_S1": 700, "R_S1": 760],
            participants: ["maksim"],
        )
        XCTAssertEqual(result, .init(names: ["R_S1": "maksim"], learnLabel: "R_S1"))
    }

    /// Seconds of diarization noise next to the real voice neither block the
    /// match nor get named.
    func testShortClusterIsIgnored() {
        let result = resolve(
            ["M_S1": "Me", "R_S1": "R_S1", "R_S2": "R_S2"],
            times: ["M_S1": 700, "R_S1": 760, "R_S2": 13],
            participants: ["maksim"],
        )
        XCTAssertEqual(result, .init(names: ["R_S1": "maksim"], learnLabel: "R_S1"))
    }

    /// Two people invited, one recognised by voice: the other is the leftover.
    func testOneKnownLeavesTheOther() {
        let result = resolve(
            ["M_S1": "Me", "R_S1": "anna", "R_S2": "R_S2"],
            times: ["M_S1": 300, "R_S1": 400, "R_S2": 500],
            participants: ["anna", "boris"],
        )
        XCTAssertEqual(result, .init(names: ["R_S2": "boris"], learnLabel: "R_S2"))
    }

    /// One far-end voice split mid-call into two long clusters: both named,
    /// only the longer learned.
    func testSplitFarEndInOneToOneLearnsTheLongerCluster() {
        let result = resolve(
            ["M_S1": "Me", "R_S1": "R_S1", "R_S2": "R_S2"],
            times: ["M_S1": 1000, "R_S1": 626, "R_S2": 804],
            participants: ["mariia"],
        )
        XCTAssertEqual(result, .init(names: ["R_S1": "mariia", "R_S2": "mariia"], learnLabel: "R_S2"))
    }

    /// Two long unknown far-end voices with one leftover of several invitees
    /// could be an uninvited person: nothing is decided.
    func testSplitIsNotAssumedOutsideAOneToOne() {
        XCTAssertNil(resolve(
            ["M_S1": "Me", "R_S1": "anna", "R_S2": "R_S2", "R_S3": "R_S3"],
            times: ["M_S1": 300, "R_S1": 400, "R_S2": 500, "R_S3": 200],
            participants: ["anna", "boris"],
        ))
    }

    func testTwoLeftoverParticipantsDecideNothing() {
        XCTAssertNil(resolve(
            ["M_S1": "Me", "R_S1": "R_S1", "R_S2": "R_S2"],
            times: ["M_S1": 300, "R_S1": 400, "R_S2": 500],
            participants: ["anna", "boris"],
        ))
    }

    func testNoParticipantsDecideNothing() {
        XCTAssertNil(resolve(["R_S1": "R_S1"], times: ["R_S1": 400], participants: []))
    }

    /// Everyone recognised: there is no one left to name.
    func testNothingUnnamedDecidesNothing() {
        XCTAssertNil(resolve(
            ["M_S1": "Me", "R_S1": "R_S1"],
            times: ["M_S1": 300, "R_S1": 10],
            participants: ["maksim"],
        ))
    }

    /// An unnamed voice in the room (mic name cleared) could be the invitee.
    func testUnnamedMicrophoneSpeakerBlocksElimination() {
        XCTAssertNil(resolve(
            ["M_S1": "M_S1", "M_S2": "M_S2", "R_S1": "R_S1"],
            times: ["M_S1": 300, "M_S2": 200, "R_S1": 400],
            participants: ["maksim"],
        ))
    }

    /// Single source: the user's voice is in the mix, so it must have been
    /// recognised for the remaining one to be the participant.
    func testSingleSourceNeedsExactlyOneUnnamedSpeaker() {
        XCTAssertEqual(
            resolve(["S1": "Me", "S2": "S2"], times: ["S1": 300, "S2": 400], participants: ["maksim"], dual: false),
            .init(names: ["S2": "maksim"], learnLabel: "S2"),
        )
        XCTAssertNil(resolve(
            ["S1": "S1", "S2": "S2"], times: ["S1": 300, "S2": 400], participants: ["maksim"], dual: false,
        ))
    }
}
