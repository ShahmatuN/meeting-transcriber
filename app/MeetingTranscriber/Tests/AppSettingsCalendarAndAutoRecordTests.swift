@testable import MeetingTranscriber
import XCTest

/// Persistence and defaults of the calendar-integration and Google Meet
/// auto-record settings. In their own file because `AppSettingsTests` sits at
/// the file-length cap; same isolated-suite idiom.
final class AppSettingsCalendarAndAutoRecordTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppSettingsCalendarAndAutoRecordTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { DefaultsSuite.remove(suiteName) }
        return suite
    }

    func testCalendarIntegrationDefaultsOffWithEveryCalendar() throws {
        let settings = try AppSettings(defaults: makeDefaults())
        XCTAssertFalse(settings.calendarIntegrationEnabled, "turning it on is what asks for calendar access")
        XCTAssertEqual(settings.calendarIDs, [], "empty means every calendar")
    }

    func testCalendarSettingsPersist() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.calendarIntegrationEnabled = true
        settings.calendarIDs = ["work-id", "team-id"]
        let fresh = AppSettings(defaults: defaults)
        XCTAssertTrue(fresh.calendarIntegrationEnabled)
        XCTAssertEqual(fresh.calendarIDs, ["work-id", "team-id"])
    }

    func testAutoRecordGoogleMeetDefaultsOffAndPersists() throws {
        // Off by default: existing installs keep prompting for every browser
        // meeting until the user opts this one call type in.
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.autoRecordGoogleMeet)
        settings.autoRecordGoogleMeet = true
        XCTAssertTrue(AppSettings(defaults: defaults).autoRecordGoogleMeet)
    }
}
