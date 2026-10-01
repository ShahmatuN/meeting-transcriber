@testable import MeetingTranscriber
import ViewInspector
import XCTest

/// One wiring test per control the Meetings feature adds: the menu item that
/// opens the window, and the live-recording card's Open and Stop buttons.
@MainActor
final class MeetingsViewTests: XCTestCase {
    private func recording(isManual: Bool) -> LiveRecordingSummary {
        // `startedAt: nil` keeps the TimelineView-driven counter out of the
        // tree; the counter is formatting, pinned in `ElapsedTimeTests`.
        LiveRecordingSummary(title: "Weekly Sync", appName: "Zoom", startedAt: nil, isManual: isManual)
    }

    func testStopOnAManualRecordingCallsTheStopAction() throws {
        var stopped = 0
        let sut = LiveRecordingCard(recording: recording(isManual: true), onOpen: {}, onStop: { stopped += 1 })

        try sut.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.meetingsStopRecording)
            .button().tap()

        XCTAssertEqual(stopped, 1)
    }

    func testAnAutoDetectedRecordingOffersNoStop() throws {
        // Stopping an auto recording early means stopping the watch loop,
        // which would also stop watching for the next meeting.
        let sut = LiveRecordingCard(recording: recording(isManual: false), onOpen: {}, onStop: {})

        XCTAssertThrowsError(
            try sut.inspect().find(viewWithAccessibilityIdentifier: A11yID.meetingsStopRecording),
        )
    }

    func testOpenCallsTheOpenAction() throws {
        var opened = 0
        let sut = LiveRecordingCard(recording: recording(isManual: false), onOpen: { opened += 1 }, onStop: {})

        try sut.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.meetingsOpenLiveRecording)
            .button().tap()

        XCTAssertEqual(opened, 1)
    }

    func testMenuItemOpensTheMeetingsWindow() throws {
        var opened = 0
        let sut = MenuBarView(
            status: nil,
            isWatching: false,
            pipelineQueue: PipelineQueue(),
            onStartStop: {},
            onRecordApp: {},
            onRecordMicrophone: {},
            noMic: false,
            manualRecordingPendingOrActive: false,
            onStopManualRecording: nil,
            onOpenLastProtocol: {},
            onOpenProtocol: { _ in },
            onOpenProtocolsFolder: {},
            onOpenSettings: {},
            onOpenMeetings: { opened += 1 },
            onNameSpeakers: nil,
            onProcessFiles: {},
            onDismissJob: { _ in },
            onQuit: {},
        )

        try sut.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.menuOpenMeetings)
            .button().tap()

        XCTAssertEqual(opened, 1)
    }
}
