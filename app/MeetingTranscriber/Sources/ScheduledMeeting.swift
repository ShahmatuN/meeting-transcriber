import Foundation

/// The calendar event a recording belongs to, as far as the calendar can say.
///
/// Produced by `CalendarMeetingMatcher` from the user's calendar and consumed
/// by `WatchLoop.handleMeeting`, which takes the title (so the protocol and the
/// output filename are named after the invitation, not after a window title
/// or a placeholder) and the attendees (speaker-naming suggestions, sidecar).
/// EventKit-free on purpose: the matcher is pure and its tests build these by
/// hand.
struct ScheduledMeeting: Equatable, Sendable {
    /// `EKEvent.eventIdentifier`. Shared by every occurrence of a recurring
    /// event, which is fine for matching and worth knowing for a consumer
    /// that reads it back out of a sidecar.
    let eventID: String
    let title: String
    /// Display names of the invited people other than the current user, in
    /// invitation order, de-duplicated. Empty when the event has no attendees.
    let attendees: [String]
    /// The conference link found on the event, if any. See
    /// `CalendarMeetingMatcher.conferenceURL(in:)`.
    let meetingURL: URL?
    let start: Date
    let end: Date

    /// Whether the conference link is a Google Meet call. The signal the
    /// browser auto-record decision keys on.
    var isGoogleMeet: Bool {
        guard let host = meetingURL?.host(percentEncoded: false)?.lowercased() else { return false }
        return host == "meet.google.com"
    }
}
