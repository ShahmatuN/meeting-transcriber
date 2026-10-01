@testable import MeetingTranscriber
import XCTest

/// What a matched calendar event changes about the job `handleMeeting`
/// enqueues. The matcher is pinned in `CalendarMeetingMatcherTests`; this
/// only proves the loop takes what it is handed and puts it where the
/// pipeline, the naming dialog and the sidecar read it.
@MainActor
final class WatchLoopCalendarTests: XCTestCase {
    private let scheduled = ScheduledMeeting(
        eventID: "evt-42",
        title: "Design Review",
        attendees: ["Alice Archer", "Bob Builder"],
        meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
        start: Date(timeIntervalSince1970: 1_780_000_000),
        end: Date(timeIntervalSince1970: 1_780_001_800),
    )

    private func makeLoop(
        scheduled: ScheduledMeeting?,
        recordOnly: Bool = false,
        recordOnlyDir: URL? = nil,
    ) -> (WatchLoop, PipelineQueue, MockRecorder) {
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/watchloop_calendar_\(UUID().uuidString)_mix.wav")
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: ImmediatelyInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.01,
            endGracePeriod: 0.01,
            maxDuration: 10,
            noMic: true,
            recordOnly: { recordOnly },
            recordOnlyDestination: { .unscoped(recordOnlyDir ?? AppPaths.recordingsDir) },
            scheduledMeeting: { _ in scheduled },
        )
        loop.permissionChecker = { .allHealthy }
        return (loop, queue, recorder)
    }

    private func teamsMeeting() -> DetectedMeeting {
        DetectedMeeting(
            pattern: .teams,
            windowTitle: "Weekly | Microsoft Teams",
            ownerName: "Microsoft Teams",
            windowPID: 9999,
        )
    }

    func testTheCalendarTitleNamesTheJob() async throws {
        let (loop, queue, _) = makeLoop(scheduled: scheduled)

        try await loop.handleMeeting(teamsMeeting())

        let job = try XCTUnwrap(queue.jobs.first)
        XCTAssertEqual(job.meetingTitle, "Design Review", "the invitation beats the window title")
        XCTAssertEqual(job.calendarEventID, "evt-42")
        XCTAssertEqual(job.participants, ["Alice Archer", "Bob Builder"])
    }

    func testWithoutAMatchTheWindowTitleIsKept() async throws {
        let (loop, queue, _) = makeLoop(scheduled: nil)

        try await loop.handleMeeting(teamsMeeting())

        let job = try XCTUnwrap(queue.jobs.first)
        XCTAssertEqual(job.meetingTitle, "Weekly", "cleaned exactly as before the calendar existed")
        XCTAssertNil(job.calendarEventID)
        XCTAssertEqual(job.participants, [])
    }

    func testTheRecordOnlySidecarCarriesTheEvent() async throws {
        let staging = try makeTempDirectory(prefix: "wl-cal-staging")
        let dir = try makeTempDirectory(prefix: "wl-cal-out")
        let (loop, _, recorder) = makeLoop(scheduled: scheduled, recordOnly: true, recordOnlyDir: dir)
        // The record-only branch moves the mix file out of staging, so it has
        // to exist, and somewhere other than the destination.
        let mix = staging.appendingPathComponent("20260503_120000_mix.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: mix)
        recorder.mixPath = mix

        try await loop.handleMeeting(teamsMeeting())

        let sidecar = try XCTUnwrap(RecordingSidecar.read(fromDirectory: dir, basename: "20260503_120000"))
        XCTAssertEqual(sidecar.version, 3)
        XCTAssertEqual(sidecar.title, "Design Review")
        XCTAssertEqual(sidecar.calendarEventID, "evt-42")
        XCTAssertEqual(sidecar.meetingURL, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(sidecar.participants, ["Alice Archer", "Bob Builder"])
    }

    // MARK: - Participant merge (pure)

    func testTheRosterLeadsAndTheInvitationFillsIn() {
        let merged = WatchLoop.mergeParticipants(
            roster: ["Bob Builder", "Carol"],
            scheduled: ["alice", "bob builder", "Carol"],
        )
        XCTAssertEqual(merged, ["Bob Builder", "Carol", "alice"])
    }

    func testAnEmptyRosterTakesTheInvitationAsIs() {
        XCTAssertEqual(WatchLoop.mergeParticipants(roster: [], scheduled: ["A", "B"]), ["A", "B"])
    }
}
