@testable import MeetingTranscriber
import XCTest

/// The auto-record branch in front of the browser consent gate, driven through
/// the real `start()`/`watchLoop()` path like `WatchLoopBrowserConsentTests`.
/// The policy itself is pinned in `BrowserAutoRecordPolicyTests`; this proves
/// the loop asks it at the right moment, with the right inputs, and that a
/// "no" from it leaves the consent path exactly as it was.
@MainActor
final class WatchLoopAutoRecordTests: XCTestCase {
    private final class FixedDetector: MeetingDetecting {
        let meeting: DetectedMeeting
        init(_ meeting: DetectedMeeting) {
            self.meeting = meeting
        }

        func checkOnce() -> DetectedMeeting? {
            meeting
        }

        func isMeetingActive(_: DetectedMeeting) -> Bool {
            true
        }

        func reset(appName _: String?) {}
    }

    private final class ConsentSpy: AppNotifying {
        private(set) var calls = 0
        let answer: ConsentAnswer
        init(answer: ConsentAnswer) {
            self.answer = answer
        }

        func notify(title _: String, body _: String, urgency _: NotificationUrgency) {}

        // swiftlint:disable async_without_await
        @MainActor
        func askToRecord(title _: String, body _: String) async -> ConsentAnswer {
            calls += 1
            return answer
        }
        // swiftlint:enable async_without_await
    }

    /// Counts tab reads, so a test can say the Apple Event was NOT sent.
    @MainActor
    private final class TabReader {
        private(set) var calls = 0
        var urls: [URL]
        init(_ urls: [URL]) {
            self.urls = urls
        }

        func read(_: String) -> [URL] {
            calls += 1
            return urls
        }
    }

    private func meetTab() throws -> URL {
        try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
    }

    private func browserMeeting(process: String = "Google Chrome") throws -> DetectedMeeting {
        let pattern = try XCTUnwrap(
            PowerAssertionDetector.defaultPatterns
                .first { $0.appName == AppMeetingPattern.browserMeetings.appName },
        )
        return DetectedMeeting(
            pattern: PowerAssertionDetector.meetingIdentity(pattern: pattern, processName: process),
            windowTitle: "\(process) Call",
            ownerName: process,
            windowPID: 5632,
        )
    }

    private func makeLoop(
        meeting: DetectedMeeting,
        spy: ConsentSpy,
        tabs: TabReader,
        enabled: Bool = true,
        scheduled: ScheduledMeeting? = nil,
        consentPolicy: BrowserConsentPolicy = BrowserConsentPolicy(),
        denyListStore: any ConsentDenyListStoring = InMemoryConsentDenyListStore(),
    ) -> (WatchLoop, MockRecorder, PipelineQueue) {
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test_autorecord_\(UUID().uuidString).wav")
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: FixedDetector(meeting),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            endGracePeriod: 0.05,
            notifier: spy,
            consentPolicy: consentPolicy,
            denyListStore: denyListStore,
            scheduledMeeting: { _ in scheduled },
            autoRecordEnabled: { enabled },
            browserTabURLs: { tabs.read($0) },
        )
        loop.permissionChecker = { .allHealthy }
        return (loop, recorder, queue)
    }

    func testAMeetTabRecordsWithoutAPrompt() async throws {
        let spy = ConsentSpy(answer: .declined)
        let tabs = try TabReader([meetTab()])
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(), spy: spy, tabs: tabs)
        loop.start()
        await waitFor(recorder.startCalled)
        XCTAssertTrue(recorder.startCalled, "a Meet tab in Chrome must start recording")
        XCTAssertEqual(spy.calls, 0, "and must not have asked")
        XCTAssertNil(loop.pendingConsentApp)
        XCTAssertEqual(loop.currentMeeting?.windowTitle, "Google Meet abc-defg-hij", "recorded under the Meet code")
        loop.stop()
    }

    func testAScheduledMeetEventRecordsWithoutTabs() async throws {
        let spy = ConsentSpy(answer: .declined)
        let tabs = TabReader([])
        let scheduled = ScheduledMeeting(
            eventID: "evt", title: "Design Review", attendees: [],
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            start: Date(), end: Date().addingTimeInterval(1800),
        )
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(), spy: spy, tabs: tabs, scheduled: scheduled)
        loop.start()
        await waitFor(recorder.startCalled)
        XCTAssertTrue(recorder.startCalled)
        XCTAssertEqual(spy.calls, 0)
        XCTAssertEqual(loop.currentMeeting?.windowTitle, "Design Review")
        loop.stop()
    }

    func testWithoutAMeetSignalThePromptIsUnchanged() async throws {
        let spy = ConsentSpy(answer: .declined)
        let tabs = try TabReader([XCTUnwrap(URL(string: "https://example.com/"))])
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(), spy: spy, tabs: tabs)
        loop.start()
        await waitFor(spy.calls >= 1)
        XCTAssertEqual(spy.calls, 1, "the consent path is what it was")
        XCTAssertFalse(recorder.startCalled)
        XCTAssertGreaterThanOrEqual(tabs.calls, 1, "the tabs were read before asking")
        loop.stop()
    }

    func testDisabledNeverReadsTabsAndPrompts() async throws {
        let spy = ConsentSpy(answer: .declined)
        let tabs = try TabReader([meetTab()])
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(), spy: spy, tabs: tabs, enabled: false)
        loop.start()
        await waitFor(spy.calls >= 1)
        XCTAssertEqual(tabs.calls, 0, "no Apple Event for a feature that is off")
        XCTAssertFalse(recorder.startCalled)
        loop.stop()
    }

    func testAnotherBrowserWithAMeetTabStillPrompts() async throws {
        let spy = ConsentSpy(answer: .declined)
        let tabs = try TabReader([meetTab()])
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(process: "Brave Browser"), spy: spy, tabs: tabs)
        loop.start()
        await waitFor(spy.calls >= 1)
        XCTAssertFalse(recorder.startCalled)
        loop.stop()
    }

    func testADeclineCooldownStopsTheTabReads() async throws {
        // After a "no", the policy is not consulted (and no Apple Event goes
        // out) until the cooldown passes: the user just answered.
        var policy = BrowserConsentPolicy()
        policy.recordDecline(app: "Google Chrome", now: Date())
        let spy = ConsentSpy(answer: .declined)
        let tabs = try TabReader([meetTab()])
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(), spy: spy, tabs: tabs, consentPolicy: policy)
        loop.start()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(tabs.calls, 0)
        XCTAssertEqual(spy.calls, 0)
        XCTAssertFalse(recorder.startCalled)
        loop.stop()
    }

    func testADeniedBrowserIsNeverAutoRecorded() async throws {
        // The deny list is applied before the policy; a Meet tab in a browser
        // the user said "Never" about changes nothing. The detector normally
        // drops the identity, so here the loop's own guard is what is pinned.
        let store = InMemoryConsentDenyListStore(denyList: ConsentDenyList(denied: ["Google Chrome"]))
        let spy = ConsentSpy(answer: .granted)
        let tabs = try TabReader([meetTab()])
        let (loop, recorder, _) = try makeLoop(meeting: browserMeeting(), spy: spy, tabs: tabs, denyListStore: store)
        loop.start()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(tabs.calls, 0)
        XCTAssertFalse(recorder.startCalled)
        XCTAssertEqual(spy.calls, 0)
        loop.stop()
    }

    func testNativeMeetingsAreUntouched() async throws {
        let spy = ConsentSpy(answer: .declined)
        let tabs = try TabReader([meetTab()])
        let zoom = DetectedMeeting(pattern: .zoom, windowTitle: "Zoom Meeting", ownerName: "zoom.us", windowPID: 1)
        let (loop, recorder, _) = makeLoop(meeting: zoom, spy: spy, tabs: tabs)
        loop.start()
        await waitFor(recorder.startCalled)
        XCTAssertEqual(tabs.calls, 0, "a native meeting never consults the browser policy")
        XCTAssertEqual(loop.currentMeeting?.windowTitle, "Zoom Meeting")
        loop.stop()
    }

    func testRetitledKeepsTheIdentity() throws {
        let original = try browserMeeting()
        let renamed = original.retitled("Google Meet abc-defg-hij")
        XCTAssertEqual(renamed.windowTitle, "Google Meet abc-defg-hij")
        XCTAssertEqual(renamed.pattern, original.pattern)
        XCTAssertEqual(renamed.ownerName, original.ownerName)
        XCTAssertEqual(renamed.windowPID, original.windowPID)
        XCTAssertEqual(renamed.detectedAt, original.detectedAt)
    }
}
