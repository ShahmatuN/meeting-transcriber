import Foundation

/// Pure decision: which calendar event, if any, is the meeting happening now.
///
/// Called once per detected meeting (not per poll) with the events of a window
/// around the current time. Everything that could be wrong about a calendar is
/// decided here, in a value type, so the tests need no EventKit and no clock.
enum CalendarMeetingMatcher {
    /// How early an event counts as "now". People join a call before the
    /// scheduled start, and a detector that fires at 09:55 for a 10:00 meeting
    /// must still find it.
    static let leadIn: TimeInterval = 600
    /// How long after its scheduled end an event still counts. Meetings run
    /// over; five minutes covers the common case without claiming the next
    /// meeting's recording for the previous slot.
    static let tail: TimeInterval = 300

    /// Hosts whose link marks an event as a video meeting. Suffix-matched, so
    /// `us02web.zoom.us` and `teams.microsoft.com` both count. Used only to
    /// prefer one overlapping event over another and to fill
    /// `ScheduledMeeting.meetingURL`; an event with no link still matches.
    static let conferenceHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com",
    ]

    /// The event happening at `now`, or nil.
    ///
    /// Candidates are timed (not all-day) events from the selected calendars
    /// whose `[start − leadIn, end + tail]` contains `now`; an empty selection
    /// means every calendar. Among overlapping candidates the one carrying a
    /// conference link wins, then the one whose start is nearest to `now`, so
    /// a focus block does not outrank the call scheduled inside it.
    static func match(
        events: [CalendarEventSummary],
        now: Date,
        selectedCalendarIDs: [String],
    ) -> ScheduledMeeting? {
        let candidates = events.filter { event in
            !event.isAllDay
                && (selectedCalendarIDs.isEmpty || selectedCalendarIDs.contains(event.calendarID))
                && event.start.addingTimeInterval(-leadIn) <= now
                && now <= event.end.addingTimeInterval(tail)
        }
        let best = candidates.min { lhs, rhs in
            let lhsHasLink = conferenceURL(in: lhs) != nil
            let rhsHasLink = conferenceURL(in: rhs) != nil
            if lhsHasLink != rhsHasLink { return lhsHasLink }
            return abs(lhs.start.timeIntervalSince(now)) < abs(rhs.start.timeIntervalSince(now))
        }
        guard let best else { return nil }
        let title = best.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduledMeeting(
            eventID: best.id,
            title: title.isEmpty ? "Calendar Meeting" : title,
            attendees: attendees(of: best),
            meetingURL: conferenceURL(in: best),
            start: best.start,
            end: best.end,
        )
    }

    /// The first conference link on the event: its URL field, then the
    /// location, then the notes, since invitations put the link in any of the
    /// three (Google Calendar fills `location` and `notes`, Outlook the notes).
    static func conferenceURL(in event: CalendarEventSummary) -> URL? {
        if let url = event.url, isConferenceURL(url) { return url }
        for text in [event.location, event.notes].compactMap(\.self) {
            if let url = urls(in: text).first(where: isConferenceURL) { return url }
        }
        return nil
    }

    /// Everyone invited except the current user, organizer included, in
    /// invitation order and without duplicates. A name that is only an e-mail
    /// address (EventKit's fallback when the invitation has no display name)
    /// is reduced to its local part, which is a usable speaker-name suggestion
    /// where `j.doe@example.com` is not.
    static func attendees(of event: CalendarEventSummary) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let people = event.attendees + (event.organizer.map { [$0] } ?? [])
        for person in people where !person.isCurrentUser {
            let name = displayName(person.name)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
        }
        return result
    }

    static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.contains(" "),
              let at = trimmed.firstIndex(of: "@") else { return trimmed }
        return String(trimmed[..<at])
    }

    static func isConferenceURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return conferenceHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// `http(s)` links in free text, in order of appearance.
    static func urls(in text: String) -> [URL] {
        let pattern = /https?:\/\/[^\s<>"'\)\]]+/
        return text.matches(of: pattern).compactMap { URL(string: String($0.output)) }
    }
}
