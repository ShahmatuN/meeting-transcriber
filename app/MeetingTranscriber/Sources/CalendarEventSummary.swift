import Foundation

/// One calendar event, reduced to what the matcher reads. The EventKit source
/// maps `EKEvent` into this at the boundary so `CalendarMeetingMatcher` and
/// its tests never touch EventKit, and so the matcher's input is a value a
/// test can spell out in full.
struct CalendarEventSummary: Equatable, Sendable {
    struct Participant: Equatable, Sendable {
        /// `EKParticipant.name`, which EventKit fills with the e-mail address
        /// when the invitation carries no display name.
        let name: String
        /// `EKParticipant.isCurrentUser`: the person whose calendar this is.
        let isCurrentUser: Bool
    }

    let id: String
    let calendarID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let attendees: [Participant]
    let organizer: Participant?
    let location: String?
    let notes: String?
    let url: URL?

    init(
        id: String,
        calendarID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        attendees: [Participant] = [],
        organizer: Participant? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.attendees = attendees
        self.organizer = organizer
        self.location = location
        self.notes = notes
        self.url = url
    }
}
