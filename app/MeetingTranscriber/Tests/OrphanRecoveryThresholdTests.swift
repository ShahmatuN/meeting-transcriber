@testable import MeetingTranscriber
import XCTest

/// The false-trigger threshold applied to crash leftovers: `recoverOrphanedRecordings`
/// judges each untracked recording by the length its header reports and deletes
/// the ones below `minimumRecoveredRecordingSeconds`, which is the same setting
/// the watch loop applies to a recording it finished itself.
@MainActor
final class OrphanRecoveryThresholdTests: XCTestCase {
    private struct Workspace {
        let tmp: URL
        let recDir: URL
    }

    private func makeWorkspace() throws -> Workspace {
        let tmp = try makeTempDirectory(prefix: "OrphanRecoveryThresholdTests")
        let recDir = tmp.appendingPathComponent("recordings")
        try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        return Workspace(tmp: tmp, recDir: recDir)
    }

    /// A readable half-second WAV under the recovery stem layout.
    private func writeShortRecording(stem: String, in ws: Workspace) throws -> (mix: URL, app: URL) {
        let source = try createTestAudioFile(in: ws.tmp)
        let mix = ws.recDir.appendingPathComponent("\(stem)_mix.wav")
        let app = ws.recDir.appendingPathComponent("\(stem)_app.wav")
        try FileManager.default.copyItem(at: source, to: mix)
        try FileManager.default.copyItem(at: source, to: app)
        return (mix, app)
    }

    func testAShortLeftoverIsDeletedInsteadOfRecovered() async throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws.tmp) }
        let files = try writeShortRecording(stem: "20261005_140054", in: ws)
        let queue = PipelineQueue(logDir: ws.tmp, minimumRecoveredRecordingSeconds: 30)
        let recDir = ws.recDir

        await queue.recoverOrphanedRecordings(recordingsDir: recDir)

        XCTAssertTrue(queue.jobs.isEmpty, "a 0.5 s leftover came back as a recovered recording")
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.mix.path), "left in staging it is rescanned on every launch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.app.path), "the whole group goes, not just the mix")
    }

    func testAZeroMinimumRecoversTheSameLeftover() async throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws.tmp) }
        let files = try writeShortRecording(stem: "20261005_140054", in: ws)
        let queue = PipelineQueue(logDir: ws.tmp)
        let recDir = ws.recDir

        await queue.recoverOrphanedRecordings(recordingsDir: recDir)

        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.mix.path))
    }

    func testALeftoverWhoseLengthCannotBeReadIsRecovered() async throws {
        // Not audio at all, so the duration is unknown. Unknown is not short:
        // deleting on a failed header read would throw away exactly the damaged
        // recordings the recovery path exists to rescue.
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws.tmp) }
        let recDir = ws.recDir
        let mix = recDir.appendingPathComponent("20261005_140136_mix.wav")
        try Data(repeating: 0xFF, count: 100).write(to: mix)
        let queue = PipelineQueue(logDir: ws.tmp, minimumRecoveredRecordingSeconds: 30)

        await queue.recoverOrphanedRecordings(recordingsDir: recDir)

        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mix.path))
    }
}
