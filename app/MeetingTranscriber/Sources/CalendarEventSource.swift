import Foundation

/// Calendar access state, EventKit-free so Settings, `/state` and the tests
/// can name it without importing the framework.
enum CalendarAuthorization: String, Equatable, Sendable {
    case notDetermined
    case denied
    case fullAccess
    /// macOS 14 can grant write-only access, which lets an app add events but
    /// read none. Useless here and reported so Settings can say why.
    case writeOnly

    /// Stable wire value for `/state.calendar.authorization`.
    var rpcValue: String {
        rawValue
    }
}

/// One of the user's calendars, as the Settings checklist shows it.
struct CalendarInfo: Identifiable, Equatable, Sendable {
    /// `EKCalendar.calendarIdentifier`, the value `AppSettings.calendarIDs` stores.
    let id: String
    let title: String
    /// The account the calendar belongs to ("iCloud", "Google"), so two
    /// calendars named "Work" can be told apart.
    let accountTitle: String?
}

/// The calendar I/O `CalendarController` sits on. `EventKitCalendarSource` is
/// the real one; tests inject a fake, and `AppState` constructed by a test
/// gets `NullCalendarSource` so no xctest process ever touches EventKit.
///
/// Main-actor isolated: `EKEventStore` is used from the main thread, the
/// controller is `@MainActor`, and nothing here is called from elsewhere.
@MainActor
protocol CalendarEventSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    /// Fires after the underlying store changed (another app edited an event,
    /// an account synced). The controller refreshes its calendar list on it.
    var onChange: (() -> Void)? { get set }
    /// Ask macOS for full read access. Prompts only when not yet determined;
    /// returns whether reading is now allowed.
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    func events(between start: Date, and end: Date) -> [CalendarEventSummary]
}

/// A source with no calendars behind it. The default for `AppState` built in
/// a test, and the fallback until the user turns the integration on.
@MainActor
final class NullCalendarSource: CalendarEventSource {
    var authorization: CalendarAuthorization = .notDetermined
    var onChange: (() -> Void)?

    // swiftlint:disable:next async_without_await
    func requestAccess() async -> Bool {
        false
    }

    func calendars() -> [CalendarInfo] {
        []
    }

    func events(between _: Date, and _: Date) -> [CalendarEventSummary] {
        []
    }
}
