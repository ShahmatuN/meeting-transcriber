import Foundation
@testable import MeetingTranscriber

/// A scripted `CalendarEventSource`: the tests set the access state, the
/// calendars and the events, and read back how often each was asked for.
@MainActor
final class FakeCalendarSource: CalendarEventSource {
    var authorization: CalendarAuthorization
    var onChange: (() -> Void)?
    var calendarList: [CalendarInfo] = []
    var eventList: [CalendarEventSummary] = []
    /// What `requestAccess` turns the authorization into when it is called.
    var grantOnRequest: CalendarAuthorization = .fullAccess

    private(set) var requestCount = 0
    private(set) var eventsQueryCount = 0
    private(set) var lastQueryRange: ClosedRange<Date>?

    init(authorization: CalendarAuthorization = .notDetermined) {
        self.authorization = authorization
    }

    // swiftlint:disable:next async_without_await
    func requestAccess() async -> Bool {
        requestCount += 1
        authorization = grantOnRequest
        return authorization == .fullAccess
    }

    func calendars() -> [CalendarInfo] {
        calendarList
    }

    func events(between start: Date, and end: Date) -> [CalendarEventSummary] {
        eventsQueryCount += 1
        lastQueryRange = start ... end
        return eventList
    }
}
