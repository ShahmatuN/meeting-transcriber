@testable import MeetingTranscriber
import XCTest

/// `DiarizationProcess.collapseToSingleSpeaker`: the pure fold the pipeline
/// applies to a microphone track whose owner has a name (`AppSettings.micName`).
/// The diarizer still ran, so the input can carry several clusters; the
/// output must carry one, and it must be the right one.
final class DiarizationCollapseTests: XCTestCase {
    private func threeClusterMic() -> DiarizationResult {
        DiarizationResult(
            segments: [
                .init(start: 0, end: 10, speaker: "SPEAKER_1"),
                .init(start: 10, end: 12, speaker: "SPEAKER_0"),
                .init(start: 12, end: 30, speaker: "SPEAKER_1"),
                .init(start: 30, end: 31, speaker: "SPEAKER_2"),
            ],
            speakingTimes: ["SPEAKER_0": 2, "SPEAKER_1": 28, "SPEAKER_2": 1],
            autoNames: ["SPEAKER_2": "Carol"],
            embeddings: ["SPEAKER_0": [1, 0, 0], "SPEAKER_1": [0, 1, 0], "SPEAKER_2": [0, 0, 1]],
        )
    }

    func testCollapseRelabelsEverySegmentToTheDominantSpeaker() {
        let collapsed = DiarizationProcess.collapseToSingleSpeaker(threeClusterMic())

        XCTAssertEqual(collapsed.segments.map(\.speaker), Array(repeating: "SPEAKER_1", count: 4))
        // Timing is untouched: the fold changes who, never when.
        XCTAssertEqual(collapsed.segments.map(\.start), [0, 10, 12, 30])
        XCTAssertEqual(collapsed.segments.map(\.end), [10, 12, 30, 31])
    }

    func testCollapseSumsSpeakingTimeUnderTheDominantSpeaker() {
        let collapsed = DiarizationProcess.collapseToSingleSpeaker(threeClusterMic())
        XCTAssertEqual(collapsed.speakingTimes, ["SPEAKER_1": 31])
    }

    func testCollapseKeepsOnlyTheDominantEmbedding() {
        // Not an average: the minority clusters are what the diarizer separated
        // out (bleed, a second voice), and averaging would fold them back in.
        let collapsed = DiarizationProcess.collapseToSingleSpeaker(threeClusterMic())
        XCTAssertEqual(collapsed.embeddings, ["SPEAKER_1": [0, 1, 0]])
    }

    func testCollapseDropsDiarizerAutoNames() {
        // The name of the collapsed speaker travels on `DiarizationRun.pinnedNames`;
        // a diarizer-side name for a minority cluster must not survive onto the
        // dominant id.
        let collapsed = DiarizationProcess.collapseToSingleSpeaker(threeClusterMic())
        XCTAssertTrue(collapsed.autoNames.isEmpty)
    }

    func testCollapseWithoutEmbeddingsStaysWithoutEmbeddings() {
        var input = threeClusterMic()
        input.embeddings = nil
        XCTAssertNil(DiarizationProcess.collapseToSingleSpeaker(input).embeddings)
    }

    func testCollapseWhenTheDominantSpeakerHasNoEmbeddingKeepsAnEmptyMap() {
        var input = threeClusterMic()
        input.embeddings = ["SPEAKER_0": [1, 0, 0]]
        // Non-nil (embeddings were produced) but empty: nothing is known about
        // the surviving speaker's voice, so nothing may be learned about it.
        XCTAssertEqual(DiarizationProcess.collapseToSingleSpeaker(input).embeddings, [:])
    }

    func testCollapseOfAnEmptyResultIsTheEmptyResult() {
        let empty = DiarizationResult(segments: [], speakingTimes: [:], autoNames: [:], embeddings: nil)
        let collapsed = DiarizationProcess.collapseToSingleSpeaker(empty)
        XCTAssertTrue(collapsed.segments.isEmpty)
        XCTAssertTrue(collapsed.speakingTimes.isEmpty)
        XCTAssertNil(collapsed.embeddings)
    }

    func testDominantSpeakerBreaksTiesByIdSoTheChoiceIsStable() {
        let tied = DiarizationResult(
            segments: [], speakingTimes: ["SPEAKER_1": 5, "SPEAKER_0": 5], autoNames: [:], embeddings: nil,
        )
        XCTAssertEqual(DiarizationProcess.dominantSpeaker(of: tied), "SPEAKER_0")
    }

    func testDominantSpeakerFallsBackToTheFirstSegmentWithoutSpeakingTimes() {
        let noTimes = DiarizationResult(
            segments: [.init(start: 0, end: 1, speaker: "SPEAKER_3")],
            speakingTimes: [:], autoNames: [:], embeddings: nil,
        )
        XCTAssertEqual(DiarizationProcess.dominantSpeaker(of: noTimes), "SPEAKER_3")
    }

    func testDominantSpeakerIsNilForNoSpeakers() {
        let empty = DiarizationResult(segments: [], speakingTimes: [:], autoNames: [:], embeddings: nil)
        XCTAssertNil(DiarizationProcess.dominantSpeaker(of: empty))
    }
}
