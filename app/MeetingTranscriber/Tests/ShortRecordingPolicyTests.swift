@testable import MeetingTranscriber
import XCTest

/// `ShortRecordingPolicy`, the pure decision behind "Discard Auto Recordings
/// Shorter Than", and `AudioFileDuration`, the header read orphan recovery
/// judges a leftover by.
final class ShortRecordingPolicyTests: XCTestCase {
    func testAnAutomaticRecordingBelowTheMinimumIsDiscarded() {
        XCTAssertTrue(ShortRecordingPolicy.discards(trigger: .auto, duration: 14, minimum: 60))
    }

    func testAnAutomaticRecordingAtTheMinimumIsKept() {
        XCTAssertFalse(ShortRecordingPolicy.discards(trigger: .auto, duration: 60, minimum: 60))
    }

    func testAManualRecordingIsNeverDiscarded() {
        // A short manual recording is deliberate; the trigger exists to tell
        // the two apart because duration alone cannot.
        XCTAssertFalse(ShortRecordingPolicy.discards(trigger: .manual, duration: 1, minimum: 60))
    }

    func testAZeroMinimumKeepsEverything() {
        XCTAssertFalse(ShortRecordingPolicy.discards(trigger: .auto, duration: 0, minimum: 0))
    }

    func testAnUnknownDurationIsKept() {
        // Nothing is discarded on a guess: a file whose length cannot be read
        // is not thereby short.
        XCTAssertFalse(ShortRecordingPolicy.discards(trigger: .auto, duration: nil, minimum: 60))
    }

    func testAudioFileDurationReadsTheHeader() throws {
        let dir = try makeTempDirectory(prefix: "ShortRecordingPolicyTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        // `createTestAudioFile` writes 8000 Float32 frames at 16 kHz.
        let wav = try createTestAudioFile(in: dir)
        let seconds = try XCTUnwrap(AudioFileDuration.seconds(of: wav))
        XCTAssertEqual(seconds, 0.5, accuracy: 0.001)
    }

    func testAudioFileDurationIsNilForSomethingThatIsNotAudio() throws {
        let dir = try makeTempDirectory(prefix: "ShortRecordingPolicyTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let junk = dir.appendingPathComponent("junk_mix.wav")
        try Data(repeating: 0xFF, count: 100).write(to: junk)
        XCTAssertNil(AudioFileDuration.seconds(of: junk))
    }
}
