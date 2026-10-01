@testable import MeetingTranscriber
import ViewInspector
import XCTest

/// Wiring tests for Settings → General → Calendar. The controller's logic is
/// pinned in `CalendarControllerTests`; this proves the section renders, the
/// switch routes through the controller (so turning it on asks for access),
/// and a calendar checkbox writes the selection.
@MainActor
final class GeneralSettingsCalendarTests: XCTestCase {
    private func makeSettings() throws -> AppSettings {
        let suiteName = "GeneralSettingsCalendarTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { DefaultsSuite.remove(suiteName) }
        return AppSettings(defaults: suite)
    }

    func testTheSectionIsHiddenWithoutAController() throws {
        let view = try GeneralSettingsView(settings: makeSettings(), notificationVisibility: nil)
        XCTAssertThrowsError(try view.inspect().find(viewWithAccessibilityIdentifier: A11yID.calendarSection))
    }

    func testTheToggleTurnsTheIntegrationOn() throws {
        let settings = try makeSettings()
        let source = FakeCalendarSource()
        let controller = CalendarController(settings: settings, source: source)
        let view = GeneralSettingsView(settings: settings, notificationVisibility: nil, calendar: controller)

        let toggle = try view.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.calendarIntegrationToggle)
            .find(ViewType.Toggle.self)
        try toggle.tap()

        // The setting is written synchronously by the binding; the access
        // request it kicks off runs in a task and is the controller's to pin.
        XCTAssertTrue(settings.calendarIntegrationEnabled)
    }

    func testACalendarCheckboxWritesTheSelection() throws {
        let settings = try makeSettings()
        settings.calendarIntegrationEnabled = true
        let source = FakeCalendarSource(authorization: .fullAccess)
        source.calendarList = [
            CalendarInfo(id: "a", title: "A", accountTitle: "iCloud"),
            CalendarInfo(id: "b", title: "B", accountTitle: nil),
        ]
        let controller = CalendarController(settings: settings, source: source)
        let view = GeneralSettingsView(settings: settings, notificationVisibility: nil, calendar: controller)

        let second = try view.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.calendarToggle(1))
            .find(ViewType.Toggle.self)
        try second.tap()

        XCTAssertEqual(settings.calendarIDs, ["a"], "unchecking B leaves the explicit set {A}")
    }

    func testADeniedGrantIsExplainedInTheSection() throws {
        let settings = try makeSettings()
        settings.calendarIntegrationEnabled = true
        let controller = CalendarController(settings: settings, source: FakeCalendarSource(authorization: .denied))
        let view = GeneralSettingsView(settings: settings, notificationVisibility: nil, calendar: controller)

        XCTAssertNoThrow(try view.inspect().find(text: "Calendar access is denied."))
    }
}
