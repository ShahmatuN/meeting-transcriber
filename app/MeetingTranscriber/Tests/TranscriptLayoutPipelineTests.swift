@testable import MeetingTranscriber
import XCTest

/// The layout a job was enqueued with, at the file it writes: the `.readable`
/// transcript opens with the header and keeps paragraphs apart, the model
/// still receives the spoken text alone, and `.compact` is byte-for-byte what
/// the app wrote before the layout existed.
@MainActor
final class TranscriptLayoutPipelineTests: XCTestCase {
    private struct Run {
        let transcript: String
        let modelInput: String?
    }

    private func run(layout: TranscriptLayout) async throws -> Run {
        let tmp = try makeTempDirectory(prefix: "TranscriptLayoutPipelineTests")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let engine = MockEngine()
        engine.segmentsByPathSuffix = [
            "app_16k.wav": [
                TimestampedSegment(start: 0, end: 5, text: "APPWORD"),
                TimestampedSegment(start: 6, end: 10, text: "APPTWO"),
            ],
            "mic_16k.wav": [TimestampedSegment(start: 20, end: 25, text: "MICWORD")],
        ]
        let diar = MockDiarization()
        diar.resultToReturn = DiarizationResult(
            segments: [.init(start: 0, end: 30, speaker: "SPEAKER_0")],
            speakingTimes: ["SPEAKER_0": 30], autoNames: [:], embeddings: nil,
        )
        let protocolGen = MockProtocolGen()
        let queue = PipelineQueue(
            engine: engine,
            diarizationFactory: { diar },
            diarizationFactoryWithMode: nil,
            protocolGeneratorFactory: { protocolGen },
            outputDir: tmp,
            logDir: tmp,
            stagingDir: AppPaths.recordingsDir,
            diarizeEnabled: true,
            numSpeakers: 0,
            micLabel: "Me",
            transcriptLayout: layout,
        )

        let audio = try createTestAudioFile(in: tmp)
        let app = tmp.appendingPathComponent("app_audio.wav")
        let mic = tmp.appendingPathComponent("mic_audio.wav")
        try FileManager.default.copyItem(at: audio, to: app)
        try FileManager.default.copyItem(at: audio, to: mic)
        queue.enqueue(PipelineJob(
            meetingTitle: "Layout: \(layout.rawValue)", appName: "Microsoft Teams",
            mixPath: audio, appPath: app, micPath: mic, micDelay: 0,
            participants: ["Kirill"],
            meetingStartTime: Date(timeIntervalSince1970: 1_790_000_000),
        ))
        await queue.processNext()

        let path = try XCTUnwrap(queue.jobs.first?.transcriptPath)
        let transcript = try String(contentsOf: path, encoding: .utf8)
        return Run(transcript: transcript, modelInput: protocolGen.capturedTranscript)
    }

    func testReadableWritesTheHeaderAndParagraphs() async throws {
        let result = try await run(layout: .readable)
        let text = result.transcript
        XCTAssertTrue(text.hasPrefix("---\ntitle: \"Layout: readable\"\n"), "got:\n\(text)")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertTrue(text.contains("date: \(formatter.string(from: Date(timeIntervalSince1970: 1_790_000_000)))"))
        XCTAssertTrue(text.contains("duration: \"0:00:25\""), "the last segment's end — got:\n\(text)")
        XCTAssertTrue(text.contains("app: \"Microsoft Teams\""))
        XCTAssertTrue(text.contains("participants: [\"Kirill\"]"))
        XCTAssertTrue(text.contains("engine: \"Mock\""))
        XCTAssertTrue(text.contains("  \"SPEAKER_0\": \"0:00:09\""), "5 s + 4 s on the app track — got:\n\(text)")
        XCTAssertTrue(text.contains("  \"Me\": \"0:00:05\""), "the named mic — got:\n\(text)")
        XCTAssertTrue(
            text.hasSuffix("---\n\n[00:00] SPEAKER_0: APPWORD APPTWO\n\n[00:20] Me: MICWORD"),
            "paragraphs separated by a blank line after the header — got:\n\(text)",
        )
    }

    func testReadableStillHandsTheModelTheSpokenTextOnly() async throws {
        let result = try await run(layout: .readable)
        let fed = try XCTUnwrap(result.modelInput)
        XCTAssertFalse(fed.hasPrefix("---"), "the header is for the file — got:\n\(fed)")
        XCTAssertTrue(fed.hasPrefix("[00:00] SPEAKER_0: APPWORD APPTWO"), "got:\n\(fed)")
    }

    func testCompactIsUnchanged() async throws {
        let result = try await run(layout: .compact)
        XCTAssertEqual(result.transcript, "[00:00] SPEAKER_0: APPWORD APPTWO\n[00:20] Me: MICWORD")
        XCTAssertEqual(result.modelInput, result.transcript)
    }
}
