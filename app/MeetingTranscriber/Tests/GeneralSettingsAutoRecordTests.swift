@testable import MeetingTranscriber
import ViewInspector
import XCTest

/// Wiring for the "Auto-record Google Meet in Chrome" toggle: it writes the
/// setting, and it sits behind the browser-meetings toggle.
@MainActor
final class GeneralSettingsAutoRecordTests: XCTestCase {
    private func makeSettings() throws -> AppSettings {
        let suiteName = "GeneralSettingsAutoRecordTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { DefaultsSuite.remove(suiteName) }
        return AppSettings(defaults: suite)
    }

    func testTheToggleWritesTheSetting() throws {
        let settings = try makeSettings()
        settings.watchBrowserMeetings = true
        let view = GeneralSettingsView(settings: settings, notificationVisibility: nil)

        let toggle = try view.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.autoRecordGoogleMeetToggle)
            .find(ViewType.Toggle.self)
        try toggle.tap()

        XCTAssertTrue(settings.autoRecordGoogleMeet)
    }

    func testTheToggleIsDisabledWithoutBrowserMeetings() throws {
        // A refinement of browser detection, not a detector of its own: with
        // browser meetings off there is nothing for it to refine.
        let settings = try makeSettings()
        let view = GeneralSettingsView(settings: settings, notificationVisibility: nil)

        let toggle = try view.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.autoRecordGoogleMeetToggle)
            .find(ViewType.Toggle.self)
        XCTAssertTrue(try toggle.isDisabled())
    }
}
