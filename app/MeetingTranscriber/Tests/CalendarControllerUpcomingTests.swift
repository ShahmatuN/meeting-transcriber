@testable import MeetingTranscriber
import XCTest

@MainActor
final class CalendarControllerUpcomingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeSettings() throws -> AppSettings {
        let suiteName = "CalendarControllerUpcomingTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { DefaultsSuite.remove(suiteName) }
        return AppSettings(defaults: suite)
    }

    private var soon: CalendarEventSummary {
        CalendarEventSummary(
            id: "e1", calendarID: "work", title: "Standup",
            start: now.addingTimeInterval(600), end: now.addingTimeInterval(1500),
        )
    }

    func testDisabledIntegrationListsNothingAndDoesNotQuery() throws {
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.eventList = [soon]
        let controller = try CalendarController(settings: makeSettings(), source: source)

        XCTAssertEqual(controller.upcomingMeetings(now: now), [])
        XCTAssertEqual(source.eventsQueryCount, 0)
    }

    func testWithoutFullAccessListsNothing() throws {
        let settings = try makeSettings()
        settings.calendarIntegrationEnabled = true
        let source = FakeCalendarSource(authorization: .denied)
        source.eventList = [soon]
        let controller = CalendarController(settings: settings, source: source)

        XCTAssertEqual(controller.upcomingMeetings(now: now), [])
    }

    func testEnabledListsTheSelectedCalendarsUpToTheEndOfToday() throws {
        let settings = try makeSettings()
        settings.calendarIntegrationEnabled = true
        settings.calendarIDs = ["work"]
        let source = FakeCalendarSource(authorization: .fullAccess)
        let other = CalendarEventSummary(
            id: "e2", calendarID: "home", title: "Dentist",
            start: now.addingTimeInterval(900), end: now.addingTimeInterval(1800),
        )
        source.eventList = [soon, other]
        let controller = CalendarController(settings: settings, source: source)

        let result = controller.upcomingMeetings(now: now)

        XCTAssertEqual(result.map(\.event.id), ["e1"])
        XCTAssertEqual(source.lastQueryRange?.upperBound, UpcomingMeetings.horizonEnd(now: now))
    }
}
