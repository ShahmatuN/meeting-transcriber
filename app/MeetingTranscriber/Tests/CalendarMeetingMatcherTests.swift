@testable import MeetingTranscriber
import XCTest

/// The pure decision behind "which calendar event is this recording".
/// Everything that can be wrong about a calendar is decided here, so these
/// run with no EventKit, no clock and no permissions.
final class CalendarMeetingMatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func event(
        id: String = "e1",
        calendar: String = "work",
        title: String = "Weekly Sync",
        startOffset: TimeInterval = -60,
        duration: TimeInterval = 1800,
        isAllDay: Bool = false,
        attendees: [CalendarEventSummary.Participant] = [],
        organizer: CalendarEventSummary.Participant? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
    ) -> CalendarEventSummary {
        CalendarEventSummary(
            id: id, calendarID: calendar, title: title,
            start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + duration),
            isAllDay: isAllDay, attendees: attendees, organizer: organizer,
            location: location, notes: notes, url: url,
        )
    }

    private func match(_ events: [CalendarEventSummary], calendars: [String] = []) -> ScheduledMeeting? {
        CalendarMeetingMatcher.match(events: events, now: now, selectedCalendarIDs: calendars)
    }

    // MARK: - Time window

    func testAnEventRunningNowMatches() {
        let result = match([event(startOffset: -300)])
        XCTAssertEqual(result?.eventID, "e1")
        XCTAssertEqual(result?.title, "Weekly Sync")
    }

    func testAnEventStartingWithinTheLeadInMatches() {
        // People join before the scheduled start; a detector that fires at
        // 09:55 for a 10:00 call must still find the call.
        XCTAssertNotNil(match([event(startOffset: CalendarMeetingMatcher.leadIn - 1)]))
    }

    func testAnEventStartingAfterTheLeadInDoesNotMatch() {
        XCTAssertNil(match([event(startOffset: CalendarMeetingMatcher.leadIn + 60)]))
    }

    func testAnEventThatEndedWithinTheTailMatches() {
        // Ended 4 minutes ago, 30 minutes long: meetings run over.
        XCTAssertNotNil(match([event(startOffset: -1800 - 240)]))
    }

    func testAnEventThatEndedAfterTheTailDoesNotMatch() {
        XCTAssertNil(match([event(startOffset: -1800 - CalendarMeetingMatcher.tail - 60)]))
    }

    func testAllDayEventsNeverMatch() {
        // A birthday or a public holiday is not the meeting being recorded.
        XCTAssertNil(match([event(startOffset: -3600, duration: 86400, isAllDay: true)]))
    }

    // MARK: - Calendar selection

    func testAnEmptySelectionMeansEveryCalendar() {
        XCTAssertNotNil(match([event(calendar: "personal", startOffset: -60)], calendars: []))
    }

    func testAnExplicitSelectionExcludesOtherCalendars() {
        XCTAssertNil(match([event(calendar: "personal", startOffset: -60)], calendars: ["work"]))
        XCTAssertNotNil(match([event(calendar: "work", startOffset: -60)], calendars: ["work"]))
    }

    // MARK: - Overlap preference

    func testAnEventWithAMeetingLinkWinsOverAnOverlappingOneWithout() {
        // A focus block spanning the day must not claim the call scheduled
        // inside it, however much closer its start is.
        let focus = event(id: "focus", title: "Focus", startOffset: -60, duration: 4 * 3600)
        let call = event(
            id: "call", title: "Design Review", startOffset: -1200,
            url: URL(string: "https://meet.google.com/abc-defg-hij"),
        )
        XCTAssertEqual(match([focus, call])?.eventID, "call")
    }

    func testAmongLinklessEventsTheNearestStartWins() {
        let far = event(id: "far", startOffset: -1500, duration: 3600)
        let near = event(id: "near", startOffset: -120, duration: 3600)
        XCTAssertEqual(match([far, near])?.eventID, "near")
    }

    // MARK: - Conference link

    func testTheLinkIsFoundInTheURLField() throws {
        let url = try XCTUnwrap(URL(string: "https://zoom.us/j/123456"))
        XCTAssertEqual(match([event(startOffset: -60, url: url)])?.meetingURL, url)
    }

    func testTheLinkIsFoundInTheLocation() {
        let result = match([event(startOffset: -60, location: "https://meet.google.com/abc-defg-hij")])
        XCTAssertEqual(result?.meetingURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(result?.isGoogleMeet, true)
    }

    func testTheLinkIsFoundInTheNotesAmongOtherText() {
        let notes = "Agenda: roadmap.\nJoin: https://us02web.zoom.us/j/987?pwd=x (passcode in invite)"
        let result = match([event(startOffset: -60, notes: notes)])
        XCTAssertEqual(result?.meetingURL?.absoluteString, "https://us02web.zoom.us/j/987?pwd=x")
        XCTAssertEqual(result?.isGoogleMeet, false)
    }

    func testANonConferenceLinkIsNotTakenForOne() {
        let result = match([event(startOffset: -60, notes: "Docs: https://example.com/spec")])
        XCTAssertNotNil(result, "the event still matches")
        XCTAssertNil(result?.meetingURL)
    }

    // MARK: - Attendees

    func testAttendeesExcludeTheCurrentUserAndKeepInvitationOrder() {
        let result = match([event(
            startOffset: -60,
            attendees: [
                .init(name: "Bob Builder", isCurrentUser: false),
                .init(name: "Me Myself", isCurrentUser: true),
                .init(name: "Alice Archer", isCurrentUser: false),
            ],
        )])
        XCTAssertEqual(result?.attendees, ["Bob Builder", "Alice Archer"])
    }

    func testTheOrganizerIsAppendedUnlessAlreadyListedOrSelf() {
        let organizer = CalendarEventSummary.Participant(name: "Carol Chair", isCurrentUser: false)
        let listed = match([event(
            startOffset: -60,
            attendees: [.init(name: "carol chair", isCurrentUser: false)],
            organizer: organizer,
        )])
        XCTAssertEqual(listed?.attendees, ["carol chair"], "case-insensitive duplicate dropped")

        let selfOrganized = match([event(
            startOffset: -60,
            attendees: [.init(name: "Dan", isCurrentUser: false)],
            organizer: .init(name: "Me", isCurrentUser: true),
        )])
        XCTAssertEqual(selfOrganized?.attendees, ["Dan"])
    }

    func testAnEmailOnlyNameIsReducedToItsLocalPart() {
        // EventKit hands back the address when the invitation carries no
        // display name; `j.doe` is a usable speaker suggestion, the address
        // is not. A name with a space is left alone even if it holds an "@".
        XCTAssertEqual(CalendarMeetingMatcher.displayName("j.doe@example.com"), "j.doe")
        XCTAssertEqual(CalendarMeetingMatcher.displayName("  Jane Doe "), "Jane Doe")
        XCTAssertEqual(CalendarMeetingMatcher.displayName("Jane @ Work"), "Jane @ Work")
    }

    func testBlankNamesAreSkipped() {
        let result = match([event(startOffset: -60, attendees: [.init(name: "  ", isCurrentUser: false)])])
        XCTAssertEqual(result?.attendees, [])
    }

    // MARK: - Title

    func testABlankTitleGetsAPlaceholder() {
        XCTAssertEqual(match([event(title: "  ", startOffset: -60)])?.title, "Calendar Meeting")
    }

    func testTheTitleIsTrimmed() {
        XCTAssertEqual(match([event(title: " Sprint Planning\n", startOffset: -60)])?.title, "Sprint Planning")
    }

    func testNoEventsMeansNoMatch() {
        XCTAssertNil(match([]))
    }
}
