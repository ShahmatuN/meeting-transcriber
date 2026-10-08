import Foundation
@testable import MeetingTranscriber
import XCTest

/// `AppSettings.transcriptLayout`: compact by default (the shape every
/// existing install writes), persisted by raw value, unknown values ignored.
final class AppSettingsTranscriptLayoutTests: XCTestCase {
    private func makeSettings(seed: String? = nil) throws -> (AppSettings, suite: String) {
        let suite = "AppSettingsTranscriptLayoutTests-\(getpid())-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if let seed { defaults.set(seed, forKey: "transcriptLayout") }
        let account = "AppSettingsTranscriptLayoutTests-openAIAPIKey-\(UUID().uuidString)"
        return (AppSettings(defaults: defaults, apiKeyAccount: account), suite)
    }

    func testDefaultsToCompact() throws {
        let (settings, suite) = try makeSettings()
        defer { DefaultsSuite.remove(suite) }
        XCTAssertEqual(settings.transcriptLayout, .compact)
    }

    func testPersistsAndReadsBackTheRawValue() throws {
        let (settings, suite) = try makeSettings()
        defer { DefaultsSuite.remove(suite) }
        settings.transcriptLayout = .readable
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(defaults.string(forKey: "transcriptLayout"), "readable")
        let (reloaded, _) = try makeSettings(seed: "readable")
        XCTAssertEqual(reloaded.transcriptLayout, .readable)
    }

    func testAnUnknownStoredValueFallsBackToCompact() throws {
        let (settings, suite) = try makeSettings(seed: "fancy")
        defer { DefaultsSuite.remove(suite) }
        XCTAssertEqual(settings.transcriptLayout, .compact)
    }
}
