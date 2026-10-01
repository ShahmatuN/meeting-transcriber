@testable import MeetingTranscriber
import XCTest

/// The pure decision behind "record this browser meeting without asking".
final class BrowserAutoRecordPolicyTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    private func meetEvent(title: String = "Design Review") -> ScheduledMeeting {
        ScheduledMeeting(
            eventID: "evt", title: title, attendees: [],
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            start: Date(), end: Date().addingTimeInterval(1800),
        )
    }

    private func zoomEvent() -> ScheduledMeeting {
        ScheduledMeeting(
            eventID: "evt", title: "Zoom Thing", attendees: [],
            meetingURL: URL(string: "https://zoom.us/j/1"),
            start: Date(), end: Date().addingTimeInterval(1800),
        )
    }

    private func decide(
        enabled: Bool = true,
        process: String = "Google Chrome",
        scheduled: ScheduledMeeting? = nil,
        tabs: [String] = [],
    ) throws -> BrowserAutoRecordPolicy.Decision {
        try BrowserAutoRecordPolicy.decide(
            enabled: enabled, processName: process, scheduled: scheduled, tabURLs: tabs.map(url),
        )
    }

    func testDisabledAlwaysAsks() throws {
        XCTAssertEqual(
            try decide(enabled: false, scheduled: meetEvent(), tabs: ["https://meet.google.com/abc-defg-hij"]),
            .ask,
        )
    }

    func testOnlyChromeIsEligibleEvenWithAMeetTab() throws {
        // The tab reader speaks to Chrome; a Brave or Edge call keeps the
        // prompt even if the calendar says Meet.
        XCTAssertEqual(try decide(process: "Brave Browser", scheduled: meetEvent()), .ask)
        XCTAssertEqual(try decide(process: "Brave Browser", tabs: ["https://meet.google.com/abc-defg-hij"]), .ask)
    }

    func testAScheduledMeetEventRecordsUnderTheCalendarTitle() throws {
        XCTAssertEqual(try decide(scheduled: meetEvent()), .autoRecord(title: "Design Review"))
    }

    func testAScheduledNonMeetEventDoesNotCount() throws {
        XCTAssertEqual(try decide(scheduled: zoomEvent()), .ask)
    }

    func testAMeetTabRecordsUnderTheCode() throws {
        XCTAssertEqual(
            try decide(tabs: ["https://mail.google.com/", "https://meet.google.com/abc-defg-hij?authuser=0"]),
            .autoRecord(title: "Google Meet abc-defg-hij"),
        )
    }

    func testTheCalendarTitleWinsWhenBothSignalsAreThere() throws {
        XCTAssertEqual(
            try decide(scheduled: meetEvent(title: "Weekly"), tabs: ["https://meet.google.com/abc-defg-hij"]),
            .autoRecord(title: "Weekly"),
        )
    }

    func testALookupAliasIsACall() throws {
        XCTAssertEqual(
            try decide(tabs: ["https://meet.google.com/lookup/team-sync"]),
            .autoRecord(title: "Google Meet team-sync"),
        )
    }

    func testTheMeetLandingPageIsNotACall() throws {
        // Chrome holds the WebRTC assertion on these too (the lobby preview);
        // without a code there is no call to record.
        for tab in ["https://meet.google.com/", "https://meet.google.com/landing", "https://meet.google.com/landing?x=1"] {
            XCTAssertEqual(try decide(tabs: [tab]), .ask, tab)
        }
    }

    func testTheHostHasToBeMeetExactly() throws {
        XCTAssertEqual(try decide(tabs: ["https://meet.google.com.evil.example/abc-defg-hij"]), .ask)
        XCTAssertEqual(try decide(tabs: ["https://example.com/abc-defg-hij"]), .ask)
    }

    func testMeetCodeShape() {
        XCTAssertTrue(BrowserAutoRecordPolicy.isMeetCode("abc-defg-hij"))
        XCTAssertFalse(BrowserAutoRecordPolicy.isMeetCode("ABC-DEFG-HIJ"))
        XCTAssertFalse(BrowserAutoRecordPolicy.isMeetCode("abc-defg-hi"))
        XCTAssertFalse(BrowserAutoRecordPolicy.isMeetCode("abc_defg_hij"))
    }

    func testNoSignalAsks() throws {
        XCTAssertEqual(try decide(), .ask)
    }
}
