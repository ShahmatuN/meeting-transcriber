@testable import MeetingTranscriber
import XCTest

/// `recordingStartedAt` / `recordingTitle`, which the Meetings window reads
/// for the live-recording card: set on the way into `.recording`, cleared on
/// the way out of it.
@MainActor
final class WatchLoopRecordingSessionTests: XCTestCase {
    func testManualRecordingCarriesItsStartAndTitleUntilStopped() async throws {
        // A frozen clock and the real sleep: the monitor's first poll is a
        // minute away, so nothing ends the recording before the test does.
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/watchloop_session_\(UUID().uuidString)_mix.wav")
        let loop = WatchLoop(
            recorderFactory: { recorder },
            pollInterval: 60,
            maxDuration: 14400,
            nowProvider: { clock.now },
            pidAliveCheck: { _ in true },
        )
        loop.permissionChecker = { .allHealthy }
        let startedAt = clock.now

        try await loop.startManualRecording(pid: 42, appName: "Zoom", title: "Weekly Sync")

        XCTAssertEqual(loop.state, .recording)
        XCTAssertEqual(loop.recordingStartedAt, startedAt)
        XCTAssertEqual(loop.recordingTitle, "Weekly Sync")

        loop.stopManualRecording()

        XCTAssertEqual(loop.state, .idle)
        XCTAssertNil(loop.recordingStartedAt)
        XCTAssertNil(loop.recordingTitle)
    }

    func testAutoDetectedMeetingIsTitledAfterTheCalendarEventWhileRecording() async throws {
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/watchloop_session_\(UUID().uuidString)_mix.wav")
        // A clock that moves on every sleep: the end-of-meeting wait measures
        // its grace period on it, so a frozen one would never let it end.
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_780_000_000))
        let start = clock.now
        let scheduled = ScheduledMeeting(
            eventID: "evt-1", title: "Grooming+Daily", attendees: [], meetingURL: nil,
            start: start, end: start.addingTimeInterval(2700),
        )
        let loop = WatchLoop(
            detector: ImmediatelyInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: PipelineQueue(),
            pollInterval: 0.01,
            endGracePeriod: 0.01,
            maxDuration: 10,
            noMic: true,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
            scheduledMeeting: { _ in scheduled },
        )
        loop.permissionChecker = { .allHealthy }
        // Read from inside the transition hook, which is where the fields are
        // committed. `handleMeeting` itself leaves the phase at `.recording`
        // (`runMeeting` moves it on), so clearing is pinned by the manual test.
        var seenWhileRecording: (title: String?, startedAt: Date?)?
        loop.onStateChange = { [weak loop] _, newState in
            if newState == .recording {
                seenWhileRecording = (loop?.recordingTitle, loop?.recordingStartedAt)
            }
        }

        try await loop.handleMeeting(DetectedMeeting(
            pattern: .teams,
            windowTitle: "Something | Microsoft Teams",
            ownerName: "Microsoft Teams",
            windowPID: 9999,
        ))

        XCTAssertEqual(seenWhileRecording?.title, "Grooming+Daily")
        XCTAssertEqual(seenWhileRecording?.startedAt, start)
    }
}
