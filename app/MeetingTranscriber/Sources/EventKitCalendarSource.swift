import EventKit
import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "EventKitCalendarSource")

/// The production `CalendarEventSource`, over one long-lived `EKEventStore`.
///
/// One store for the process: EventKit keys its change notifications and its
/// cached calendars to the store instance, and a store created per call would
/// re-read the database each time. Constructed only from the real entry point
/// (`MeetingTranscriberApp`), never from a test: creating a store does not
/// prompt, but the first `requestFullAccessToEvents()` does, and an xctest
/// process has no usage string to show for it.
@MainActor
final class EventKitCalendarSource: CalendarEventSource {
    private let store = EKEventStore()
    private var observer: (any NSObjectProtocol)?
    var onChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var authorization: CalendarAuthorization {
        // A plain `default` rather than `@unknown default`, so the deprecated
        // pre-14 `.authorized` case need not be named (the deployment floor is
        // 14, where it is never returned).
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                accountTitle: calendar.source?.title,
            )
        }
    }

    func events(between start: Date, and end: Date) -> [CalendarEventSummary] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.summary)
    }

    private static func summary(_ event: EKEvent) -> CalendarEventSummary {
        CalendarEventSummary(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            attendees: (event.attendees ?? []).map(participant),
            organizer: event.organizer.map(participant),
            location: event.location,
            notes: event.notes,
            url: event.url,
        )
    }

    private static func participant(_ person: EKParticipant) -> CalendarEventSummary.Participant {
        CalendarEventSummary.Participant(name: person.name ?? "", isCurrentUser: person.isCurrentUser)
    }
}
