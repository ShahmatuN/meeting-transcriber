@testable import MeetingTranscriber
import XCTest

final class UpcomingMeetingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private var horizon: Date {
        now.addingTimeInterval(6 * 3600)
    }

    private func event(
        _ id: String,
        startOffset: TimeInterval,
        duration: TimeInterval = 1800,
        calendar: String = "work",
        isAllDay: Bool = false,
        url: URL? = nil,
    ) -> CalendarEventSummary {
        CalendarEventSummary(
            id: id, calendarID: calendar, title: id,
            start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + duration),
            isAllDay: isAllDay, url: url,
        )
    }

    private func select(_ events: [CalendarEventSummary], calendars: [String] = []) -> [UpcomingMeeting] {
        UpcomingMeetings.select(events: events, now: now, horizonEnd: horizon, selectedCalendarIDs: calendars)
    }

    func testKeepsRunningAndLaterEventsInStartOrder() {
        let result = select([
            event("later", startOffset: 3600),
            event("running", startOffset: -600),
            event("soon", startOffset: 900),
        ])

        XCTAssertEqual(result.map(\.event.id), ["running", "soon", "later"])
        XCTAssertEqual(result.map(\.isNow), [true, false, false])
    }

    func testDropsEndedAllDayAndPastTheHorizon() {
        let result = select([
            event("ended", startOffset: -3600, duration: 1800),
            event("endsNow", startOffset: -1800, duration: 1800),
            event("allDay", startOffset: -3600, duration: 86400, isAllDay: true),
            event("tomorrow", startOffset: 7 * 3600),
            event("kept", startOffset: 600),
        ])

        XCTAssertEqual(result.map(\.event.id), ["kept"])
    }

    func testEmptySelectionMeansEveryCalendar() {
        let events = [event("a", startOffset: 60, calendar: "work"), event("b", startOffset: 120, calendar: "home")]

        XCTAssertEqual(select(events).map(\.event.id), ["a", "b"])
        XCTAssertEqual(select(events, calendars: ["home"]).map(\.event.id), ["b"])
    }

    func testCarriesTheConferenceLink() throws {
        let meet = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let result = select([
            event("call", startOffset: 60, url: meet),
            event("lunch", startOffset: 120),
        ])

        XCTAssertEqual(result.first?.conferenceURL, meet)
        XCTAssertNil(result.last?.conferenceURL)
    }

    func testOccurrencesOfOneRecurringEventGetDistinctIDs() {
        let first = event("standup", startOffset: 60)
        let second = CalendarEventSummary(
            id: "standup", calendarID: "work", title: "standup",
            start: now.addingTimeInterval(3600), end: now.addingTimeInterval(4500),
        )

        let ids = select([first, second]).map(\.id)

        XCTAssertEqual(Set(ids).count, 2)
    }

    func testHorizonIsTheEndOfTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))

        XCTAssertEqual(UpcomingMeetings.horizonEnd(now: noon, calendar: calendar), midnight)
    }
}
