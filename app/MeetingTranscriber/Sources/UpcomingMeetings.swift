import Foundation

/// A calendar event the Meetings window shows under "Coming up".
struct UpcomingMeeting: Identifiable, Equatable {
    let event: CalendarEventSummary
    /// Whether the event is running at the moment of selection.
    let isNow: Bool
    /// The conference link found on the event, for the Join button.
    let conferenceURL: URL?

    var id: String {
        // An `eventIdentifier` is shared by every occurrence of a recurring
        // event, so the start disambiguates two occurrences in one list.
        "\(event.id)@\(event.start.timeIntervalSinceReferenceDate)"
    }
}

/// The pure "Coming up" decision: what is left of today, from the calendars
/// the user selected for the integration.
enum UpcomingMeetings {
    /// Timed events from the selected calendars (empty = all) that have not
    /// ended and start before `horizonEnd`, ordered by start. All-day events
    /// are left out: they are days off and reminders, not meetings to record.
    static func select(
        events: [CalendarEventSummary],
        now: Date,
        horizonEnd: Date,
        selectedCalendarIDs: [String],
    ) -> [UpcomingMeeting] {
        events
            .filter { event in
                !event.isAllDay
                    && event.end > now
                    && event.start < horizonEnd
                    && (selectedCalendarIDs.isEmpty || selectedCalendarIDs.contains(event.calendarID))
            }
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.title < rhs.title : lhs.start < rhs.start
            }
            .map { event in
                UpcomingMeeting(
                    event: event,
                    isNow: event.start <= now,
                    conferenceURL: CalendarMeetingMatcher.conferenceURL(in: event),
                )
            }
    }

    /// The end of the "Coming up" window: the end of the day containing `now`.
    static func horizonEnd(now: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(86400)
    }
}
