@testable import MeetingTranscriber
import XCTest

/// `AppSettings.askToNameSpeakers == false`: a diarized job finishes on its
/// auto-names instead of parking for the "Name Speakers" dialog, and leaves
/// none of the files that only the dialog reads.
@MainActor
final class NamingDialogOffTests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = try makeTempDirectory(prefix: "naming_dialog_off")
    }

    override func tearDown() async throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        tmpDir = nil
        try await super.tearDown()
    }

    private func makeQueue(asks: Bool, engine: MockEngine = MockEngine()) -> PipelineQueue {
        let diarization = MockDiarization()
        diarization.resultToReturn = DiarizationResult(
            segments: [.init(start: 0, end: 5, speaker: "SPEAKER_0")],
            speakingTimes: ["SPEAKER_0": 5],
            autoNames: [:],
            embeddings: ["SPEAKER_0": [1, 0, 0]],
        )
        let askSetting: () -> Bool = { asks }
        return PipelineQueue(
            engine: engine,
            diarizationFactory: { diarization },
            protocolGeneratorFactory: { MockProtocolGen() },
            outputDir: tmpDir,
            logDir: tmpDir,
            diarizeEnabled: true,
            askToNameSpeakers: askSetting,
        )
    }

    private func recordingFiles() -> [String] {
        let dir = tmpDir.appendingPathComponent("recordings")
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    func testDiarizedJobFinishesWithoutParkingAndDropsDialogFiles() async throws {
        let engine = MockEngine()
        engine.segmentsToReturn = [TimestampedSegment(start: 0, end: 5, text: "Hello")]
        let queue = makeQueue(asks: false, engine: engine)

        let job = try PipelineJob(
            meetingTitle: "No Dialog", appName: "Teams",
            mixPath: createTestAudioFile(in: tmpDir), appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)
        await queue.processNext()

        XCTAssertEqual(queue.jobs.first?.state, .done)
        XCTAssertNil(queue.speakerNamingDataByJob[job.id], "nothing is parked for a dialog")
        let files = recordingFiles()
        for suffix in ["_naming.json", "_16k.wav", "_segments.json"] {
            XCTAssertFalse(files.contains { $0.hasSuffix(suffix) }, "left a dialog-only \(suffix): \(files)")
        }
    }

    /// The control: with the dialog on, the same job parks as before.
    func testDiarizedJobStillParksWhenTheDialogIsOn() async throws {
        let engine = MockEngine()
        engine.segmentsToReturn = [TimestampedSegment(start: 0, end: 5, text: "Hello")]
        let queue = makeQueue(asks: true, engine: engine)

        let job = try PipelineJob(
            meetingTitle: "With Dialog", appName: "Teams",
            mixPath: createTestAudioFile(in: tmpDir), appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)
        await queue.processNext()

        XCTAssertEqual(queue.jobs.first?.state, .speakerNamingPending)
        XCTAssertTrue(recordingFiles().contains { $0.hasSuffix("_16k.wav") })
    }

    /// A job parked before the dialog was turned off is resolved on restore,
    /// as a Skip would, instead of reopening the window.
    func testRestoredPendingJobIsResolvedOnLoad() throws {
        var job = PipelineJob(
            meetingTitle: "Parked Earlier", appName: "Teams",
            mixPath: nil, appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .speakerNamingPending
        job.namingSlug = "parked_earlier"
        try JSONEncoder().encode([job])
            .write(to: tmpDir.appendingPathComponent(PipelineSnapshot.snapshotFilename))
        let store = SpeakerNamingStore(outputDir: tmpDir)
        try store.save(
            PipelineQueue.SpeakerNamingData(
                jobID: job.id, meetingTitle: "Parked Earlier",
                mapping: ["SPEAKER_0": "SPEAKER_0"], speakingTimes: ["SPEAKER_0": 5],
                embeddings: [:], audioPath: nil, segments: [], participants: [],
                isDualSource: false,
            ),
            slug: "parked_earlier",
        )

        let queue = makeQueue(asks: false)
        queue.loadSnapshot()

        XCTAssertEqual(queue.jobs.first?.state, .done)
        XCTAssertTrue(queue.pendingSpeakerNamingJobs.isEmpty)
        XCTAssertFalse(store.hasNamingData(slug: "parked_earlier"), "the sidecar of a resolved job is gone")
    }
}
