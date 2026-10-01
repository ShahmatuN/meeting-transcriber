@testable import MeetingTranscriber
import XCTest

/// The calendar's contribution to the protocol prompt: one preamble block
/// that tells the model the title and the invitees are authoritative, and
/// nothing at all when the calendar had nothing for the recording.
final class ProtocolGeneratorScheduledContextTests: XCTestCase {
    private func tempPrompt(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheduled-\(UUID().uuidString).md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testNoScheduledContextLeavesThePromptUnchanged() throws {
        // Byte-identical to the pre-calendar prompt, so imports, manual
        // recordings and unmatched meetings are not affected by this feature.
        let url = try tempPrompt("Body {LANGUAGE}.")
        let without = ProtocolGenerator.buildSystemPrompt(
            diarized: false, language: "German", meetingStartTime: nil, promptURL: url,
        )
        let explicitNil = ProtocolGenerator.buildSystemPrompt(
            diarized: false, language: "German", meetingStartTime: nil, scheduled: nil, promptURL: url,
        )
        XCTAssertEqual(without, "Body German.")
        XCTAssertEqual(explicitNil, without)
    }

    func testScheduledContextJoinsTheMetadataBlock() throws {
        let url = try tempPrompt("Body.")
        let startTime = try localDate(2026, 8, 21, 13, 28)
        let prompt = ProtocolGenerator.buildSystemPrompt(
            diarized: false,
            language: "German",
            meetingStartTime: startTime,
            scheduled: .init(title: "Design Review", participants: ["Alice", "Bob"]),
            promptURL: url,
        )
        XCTAssertEqual(
            prompt,
            """
            Meeting metadata:
            Date: 2026-08-21
            Time: 13:28
            The date and time above are authoritative. Interpret relative time expressions
            in the transcript relative to this meeting date. Do not rely on the model's
            assumed current date.
            Scheduled meeting: Design Review
            Invited participants: Alice, Bob
            Use the scheduled title as the meeting title and prefer the invited names when identifying speakers.

            Body.
            """,
        )
    }

    func testScheduledContextWithoutAStartTimeStillOpensTheBlock() throws {
        // A record-only sidecar reimported with a calendar event but no
        // reliable start (it has one, but the rule is per field): the block
        // still needs its heading, and no participants line when there are none.
        let url = try tempPrompt("Body.")
        let prompt = ProtocolGenerator.buildSystemPrompt(
            diarized: false,
            language: "German",
            meetingStartTime: nil,
            scheduled: .init(title: "Solo Planning", participants: []),
            promptURL: url,
        )
        XCTAssertTrue(prompt.hasPrefix("Meeting metadata:\nScheduled meeting: Solo Planning\n"))
        XCTAssertFalse(prompt.contains("Invited participants"))
        XCTAssertTrue(prompt.hasSuffix("\n\nBody."))
    }
}
