import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "CalendarController")

/// The calendar concern: access state, the calendar list Settings shows, and
/// the one question the watch loop asks, "which event is happening now".
///
/// Sits over a `CalendarEventSource` so the EventKit I/O is injectable, and
/// over `AppSettings` for the two persisted values (`calendarIntegrationEnabled`,
/// `calendarIDs`). Owned by `AppState`, read by Settings → General, and handed
/// to `WatchLoop` as the `scheduledMeeting` closure.
@Observable
@MainActor
final class CalendarController {
    private let settings: AppSettings
    private let source: any CalendarEventSource

    private(set) var authorization: CalendarAuthorization
    /// Every calendar the account exposes, for the Settings checklist. Empty
    /// until access is granted.
    private(set) var availableCalendars: [CalendarInfo] = []
    /// The event the last `scheduledMeeting(at:)` call matched, for `/state`.
    private(set) var lastMatchedEventID: String?

    /// How far either side of "now" the event query reaches. Generous because
    /// the matcher applies the real window (`leadIn`/`tail`); this only has to
    /// be wide enough to contain it, and a long meeting that started an hour
    /// ago is still happening.
    static let queryHalfWidth: TimeInterval = 4 * 3600

    init(settings: AppSettings, source: any CalendarEventSource) {
        self.settings = settings
        self.source = source
        self.authorization = source.authorization
        source.onChange = { [weak self] in self?.refresh() }
        if settings.calendarIntegrationEnabled { refresh() }
    }

    var isEnabled: Bool {
        settings.calendarIntegrationEnabled
    }

    /// Turn the integration on or off. Turning it on is what asks macOS for
    /// access, so the prompt appears while the user is looking at the switch
    /// that caused it rather than in the middle of a meeting.
    func setEnabled(_ enabled: Bool) async {
        settings.calendarIntegrationEnabled = enabled
        guard enabled else { return }
        await activate()
    }

    /// Ask for access if macOS has not been asked yet, then re-read the
    /// calendar list. The Settings toggle writes the setting itself and calls
    /// this in a task, so the switch flips synchronously and the prompt follows.
    func activate() async {
        if source.authorization == .notDetermined {
            let granted = await source.requestAccess()
            logger.info("Calendar access requested, granted=\(granted, privacy: .public)")
        }
        refresh()
    }

    /// Re-read access state and the calendar list.
    func refresh() {
        authorization = source.authorization
        availableCalendars = authorization == .fullAccess ? source.calendars() : []
    }

    /// Whether the checklist shows this calendar as included. An empty
    /// `calendarIDs` means every calendar, so enabling the integration needs
    /// no clicks; unchecking one writes the explicit remaining set.
    func isCalendarSelected(_ id: String) -> Bool {
        settings.calendarIDs.isEmpty || settings.calendarIDs.contains(id)
    }

    /// Include or exclude one calendar. Refuses to exclude the last remaining
    /// one: an empty list would read as "all calendars" again, which is the
    /// opposite of what the click meant.
    func setCalendar(_ id: String, selected: Bool) {
        var ids = settings.calendarIDs.isEmpty ? availableCalendars.map(\.id) : settings.calendarIDs
        if selected {
            if !ids.contains(id) { ids.append(id) }
        } else {
            let remaining = ids.filter { $0 != id }
            guard !remaining.isEmpty else { return }
            ids = remaining
        }
        settings.calendarIDs = ids
    }

    /// The event happening at `now`, or nil when the integration is off,
    /// access is missing, or nothing matches. Reads the store once per call;
    /// the watch loop calls it once per detected meeting.
    func scheduledMeeting(at now: Date) -> ScheduledMeeting? {
        guard settings.calendarIntegrationEnabled, source.authorization == .fullAccess else {
            return nil
        }
        let events = source.events(
            between: now.addingTimeInterval(-Self.queryHalfWidth),
            and: now.addingTimeInterval(Self.queryHalfWidth),
        )
        let match = CalendarMeetingMatcher.match(
            events: events, now: now, selectedCalendarIDs: settings.calendarIDs,
        )
        lastMatchedEventID = match?.eventID
        if let match {
            logger.info("Matched calendar event \(match.eventID, privacy: .public) with \(match.attendees.count) attendees")
        }
        return match
    }

    /// What is left of today, for the Meetings window's "Coming up" card.
    /// Empty when the integration is off or access is missing, the same gate
    /// as `scheduledMeeting(at:)`. Reads the store once per call; the window
    /// calls it on open and once a minute while it is open.
    func upcomingMeetings(now: Date) -> [UpcomingMeeting] {
        guard settings.calendarIntegrationEnabled, source.authorization == .fullAccess else {
            return []
        }
        let horizonEnd = UpcomingMeetings.horizonEnd(now: now)
        let events = source.events(between: now.addingTimeInterval(-Self.queryHalfWidth), and: horizonEnd)
        return UpcomingMeetings.select(
            events: events, now: now, horizonEnd: horizonEnd, selectedCalendarIDs: settings.calendarIDs,
        )
    }
}
