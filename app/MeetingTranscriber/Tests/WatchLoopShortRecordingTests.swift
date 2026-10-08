@testable import MeetingTranscriber
import XCTest

/// The false-trigger threshold at the point where a finished recording becomes
/// a pipeline job: an automatic recording shorter than
/// `minimumAutoRecordingSeconds` is deleted and reported instead of enqueued,
/// a manual one is enqueued whatever its length.
@MainActor
final class WatchLoopShortRecordingTests: XCTestCase {
    private struct Fixture {
        let dir: URL
        let recorder: MockRecorder
        let mix: URL
        let app: URL
    }

    /// A recorder whose stop() hands back two real files in a throwaway
    /// directory, so the test can see whether they survive.
    private func makeFixture() throws -> Fixture {
        let dir = try makeTempDirectory(prefix: "WatchLoopShortRecordingTests")
        let recorder = MockRecorder()
        let mix = dir.appendingPathComponent("short_mix.wav")
        let app = dir.appendingPathComponent("short_app.wav")
        try Data(repeating: 0, count: 64).write(to: mix)
        try Data(repeating: 0, count: 64).write(to: app)
        recorder.mixPath = mix
        recorder.appPath = app
        return Fixture(dir: dir, recorder: recorder, mix: mix, app: app)
    }

    /// An auto-detected meeting that ends within a few virtual seconds, judged
    /// against a one-minute minimum.
    private func runShortAutoMeeting(
        recorder: MockRecorder, queue: PipelineQueue, notifier: RecordingNotifier, minimum: TimeInterval,
    ) async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_780_000_000))
        let loop = WatchLoop(
            detector: ImmediatelyInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.5,
            endGracePeriod: 0.5,
            maxDuration: 10,
            noMic: true,
            minimumAutoRecordingSeconds: { minimum },
            notifier: notifier,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        loop.permissionChecker = { .allHealthy }
        try await loop.handleMeeting(DetectedMeeting(
            pattern: .teams, windowTitle: "Lobby | Microsoft Teams",
            ownerName: "Microsoft Teams", windowPID: 9999,
        ))
    }

    func testAShortAutomaticRecordingIsDeletedReportedAndNotEnqueued() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let queue = PipelineQueue()
        let notifier = RecordingNotifier()

        try await runShortAutoMeeting(recorder: fixture.recorder, queue: queue, notifier: notifier, minimum: 60)

        XCTAssertTrue(queue.jobs.isEmpty, "a false trigger must not become a job — got: \(queue.jobs.map(\.meetingTitle))")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.mix.path), "the mix stays and is re-picked as an orphan")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app.path), "the app track is collected by nothing")
        XCTAssertEqual(notifier.calls.count, 1)
        XCTAssertEqual(notifier.calls.first?.title, "Short Recording Discarded")
        XCTAssertEqual(notifier.calls.first?.urgency, .standard, "a recording that never was is nothing to act on")
    }

    func testAZeroMinimumEnqueuesTheSameRecording() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let queue = PipelineQueue()
        let notifier = RecordingNotifier()

        try await runShortAutoMeeting(recorder: fixture.recorder, queue: queue, notifier: notifier, minimum: 0)

        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.mix.path))
        XCTAssertTrue(notifier.calls.isEmpty)
    }

    func testAShortManualRecordingIsEnqueuedDespiteTheMinimum() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let recorder = fixture.recorder
        let queue = PipelineQueue()
        let notifier = RecordingNotifier()
        // A frozen clock: the recording lasts zero seconds by the loop's own
        // measure, which is as short as it gets.
        let clock = TestClock()
        let loop = WatchLoop(
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 60,
            maxDuration: 14400,
            minimumAutoRecordingSeconds: { 60 },
            notifier: notifier,
            nowProvider: { clock.now },
            pidAliveCheck: { _ in true },
        )
        loop.permissionChecker = { .allHealthy }

        try await loop.startManualRecording(pid: 42, appName: "Zoom", title: "Quick Note")
        loop.stopManualRecording()

        XCTAssertEqual(queue.jobs.count, 1, "a short manual recording is deliberate")
        XCTAssertTrue(notifier.calls.isEmpty)
    }
}
