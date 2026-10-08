import Foundation
@testable import MeetingTranscriber
import XCTest

/// `AppSettings.minimumAutoRecordingSeconds`: its default and its floor. Its
/// own file because `AppSettingsTests` sits on the file-length cap.
final class AppSettingsRecordingThresholdTests: XCTestCase {
    private func makeSettings() throws -> (AppSettings, suite: String) {
        let suite = "AppSettingsRecordingThresholdTests-\(getpid())-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let account = "AppSettingsRecordingThresholdTests-openAIAPIKey-\(UUID().uuidString)"
        return (AppSettings(defaults: defaults, apiKeyAccount: account), suite)
    }

    func testDefaultsToOneMinute() throws {
        let (settings, suite) = try makeSettings()
        defer { DefaultsSuite.remove(suite) }
        XCTAssertEqual(settings.minimumAutoRecordingSeconds, 60.0)
    }

    func testClampsAtZero() throws {
        // 0 is "keep everything" and the floor; a negative value has no meaning.
        let (settings, suite) = try makeSettings()
        defer { DefaultsSuite.remove(suite) }
        settings.minimumAutoRecordingSeconds = -5
        XCTAssertEqual(settings.minimumAutoRecordingSeconds, 0)
        settings.minimumAutoRecordingSeconds = 0
        XCTAssertEqual(settings.minimumAutoRecordingSeconds, 0)
    }

    func testPersistsThroughDefaults() throws {
        let (settings, suite) = try makeSettings()
        defer { DefaultsSuite.remove(suite) }
        settings.minimumAutoRecordingSeconds = 120
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(defaults.object(forKey: "minimumAutoRecordingSeconds") as? Double, 120)
    }
}
