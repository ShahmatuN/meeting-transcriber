@testable import MeetingTranscriber
import XCTest

@MainActor
final class CalendarControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeSettings() throws -> AppSettings {
        let suiteName = "CalendarControllerTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { DefaultsSuite.remove(suiteName) }
        return AppSettings(defaults: suite)
    }

    private func runningEvent(id: String = "e1", calendar: String = "work") -> CalendarEventSummary {
        CalendarEventSummary(
            id: id, calendarID: calendar, title: "Standup",
            start: now.addingTimeInterval(-300), end: now.addingTimeInterval(1500),
            attendees: [.init(name: "Alice", isCurrentUser: false)],
        )
    }

    // MARK: - Enabling

    func testEnablingRequestsAccessOnceAndLoadsCalendars() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource()
        source.calendarList = [CalendarInfo(id: "work", title: "Work", accountTitle: "iCloud")]
        let controller = CalendarController(settings: settings, source: source)

        await controller.setEnabled(true)

        XCTAssertTrue(settings.calendarIntegrationEnabled)
        XCTAssertEqual(source.requestCount, 1)
        XCTAssertEqual(controller.authorization, .fullAccess)
        XCTAssertEqual(controller.availableCalendars.map(\.id), ["work"])
    }

    func testEnablingWhenAlreadyGrantedDoesNotAskAgain() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        let controller = CalendarController(settings: settings, source: source)

        await controller.setEnabled(true)

        XCTAssertEqual(source.requestCount, 0, "a granted store is not re-prompted")
    }

    func testADeniedRequestLeavesTheSettingOnButNothingMatches() async throws {
        // The switch stays where the user put it so Settings can explain the
        // denial next to it; the lookup must fail closed meanwhile.
        let settings = try makeSettings()
        let source = FakeCalendarSource()
        source.grantOnRequest = .denied
        source.eventList = [runningEvent()]
        let controller = CalendarController(settings: settings, source: source)

        await controller.setEnabled(true)

        XCTAssertTrue(settings.calendarIntegrationEnabled)
        XCTAssertEqual(controller.authorization, .denied)
        XCTAssertNil(controller.scheduledMeeting(at: now))
        XCTAssertEqual(source.eventsQueryCount, 0, "no access, no query")
    }

    func testDisabledNeverQueriesTheStore() throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.eventList = [runningEvent()]
        let controller = CalendarController(settings: settings, source: source)

        XCTAssertNil(controller.scheduledMeeting(at: now))
        XCTAssertEqual(source.eventsQueryCount, 0)
    }

    // MARK: - Lookup

    func testScheduledMeetingMatchesAndRecordsTheEventID() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.eventList = [runningEvent()]
        let controller = CalendarController(settings: settings, source: source)
        await controller.setEnabled(true)

        let match = controller.scheduledMeeting(at: now)

        XCTAssertEqual(match?.title, "Standup")
        XCTAssertEqual(match?.attendees, ["Alice"])
        XCTAssertEqual(controller.lastMatchedEventID, "e1")
        let range = try XCTUnwrap(source.lastQueryRange)
        XCTAssertTrue(range.contains(now), "the query window is centred on the instant asked about")
    }

    func testTheSelectedCalendarsFilterTheLookup() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.eventList = [runningEvent(calendar: "personal")]
        let controller = CalendarController(settings: settings, source: source)
        await controller.setEnabled(true)
        settings.calendarIDs = ["work"]

        XCTAssertNil(controller.scheduledMeeting(at: now))
        XCTAssertNil(controller.lastMatchedEventID)
    }

    // MARK: - Calendar selection

    func testAnEmptySelectionShowsEveryCalendarAsSelected() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.calendarList = [
            CalendarInfo(id: "a", title: "A", accountTitle: nil),
            CalendarInfo(id: "b", title: "B", accountTitle: nil),
        ]
        let controller = CalendarController(settings: settings, source: source)
        await controller.setEnabled(true)

        XCTAssertTrue(controller.isCalendarSelected("a"))
        XCTAssertTrue(controller.isCalendarSelected("b"))
    }

    func testUncheckingOneCalendarWritesTheExplicitRemainingSet() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.calendarList = [
            CalendarInfo(id: "a", title: "A", accountTitle: nil),
            CalendarInfo(id: "b", title: "B", accountTitle: nil),
        ]
        let controller = CalendarController(settings: settings, source: source)
        await controller.setEnabled(true)

        controller.setCalendar("a", selected: false)

        XCTAssertEqual(settings.calendarIDs, ["b"])
        XCTAssertFalse(controller.isCalendarSelected("a"))
        XCTAssertTrue(controller.isCalendarSelected("b"))
    }

    func testTheLastCalendarCannotBeUnchecked() async throws {
        // An empty list would read as "all calendars" again, the opposite of
        // what the click meant.
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.calendarList = [CalendarInfo(id: "a", title: "A", accountTitle: nil)]
        let controller = CalendarController(settings: settings, source: source)
        await controller.setEnabled(true)

        controller.setCalendar("a", selected: false)

        XCTAssertEqual(settings.calendarIDs, [])
        XCTAssertTrue(controller.isCalendarSelected("a"))
    }

    func testReCheckingACalendarAppendsIt() throws {
        let settings = try makeSettings()
        settings.calendarIDs = ["b"]
        let source = FakeCalendarSource(authorization: .fullAccess)
        let controller = CalendarController(settings: settings, source: source)

        controller.setCalendar("a", selected: true)

        XCTAssertEqual(settings.calendarIDs, ["b", "a"])
    }

    // MARK: - Store changes

    func testAStoreChangeRefreshesTheCalendarList() async throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource(authorization: .fullAccess)
        let controller = CalendarController(settings: settings, source: source)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.availableCalendars, [])

        source.calendarList = [CalendarInfo(id: "new", title: "New", accountTitle: nil)]
        source.onChange?()

        XCTAssertEqual(controller.availableCalendars.map(\.id), ["new"])
    }
}
