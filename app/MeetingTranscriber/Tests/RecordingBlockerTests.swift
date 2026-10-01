@testable import MeetingTranscriber
import XCTest

/// Which permission problems have to stop a recording from starting, as opposed
/// to only degrading a side feature. Deliberately a different question from the
/// aggregate `isHealthy` in `PermissionHealthCheckTests`: these two must be able
/// to disagree, and several of the assertions below exist to pin exactly that.
final class RecordingBlockerTests: XCTestCase {
    func testAccessibilityProblemsDoNotBlockRecording() {
        for status in [PermissionStatus.denied, .broken] {
            let result = PermissionHealthCheck.overallHealth(
                screenRecording: .healthy,
                microphone: .healthy,
                accessibility: status,
            )
            // The menu bar badge and the permission notification still report a
            // problem, the recording gate does not. Anything that collapses the
            // two notions back together breaks here.
            XCTAssertFalse(result.isHealthy, "accessibility \(status) is still a reported problem")
            XCTAssertTrue(result.recordingBlockers(for: .appAndMic(pid: 1)).isEmpty)
            XCTAssertNil(result.recordingRefusalReason(for: .appAndMic(pid: 1)))
        }
    }

    func testMicrophoneProblemsBlockRecording() {
        for (status, problem) in [
            (PermissionStatus.denied, PermissionProblem.microphoneDenied),
            (.broken, .microphoneBroken),
        ] {
            let result = PermissionHealthCheck.overallHealth(screenRecording: .healthy, microphone: status)
            XCTAssertEqual(result.recordingBlockers(for: .appAndMic(pid: 1)), [problem])
            XCTAssertNotNil(result.recordingRefusalReason(for: .appAndMic(pid: 1)))
        }
    }

    func testDeniedScreenRecordingIsNotAProblemAndBlocksNothing() {
        // Screen Recording only improves meeting titles. The app-audio tap runs
        // on the separate Audio Recording grant, which cannot be preflighted, so
        // the proxy block this grant used to carry over-refused exactly the
        // recommended configuration (Audio Recording granted, Screen Recording
        // withheld). Neither the badge nor the gate may mention it now.
        for status in [PermissionStatus.denied, .broken] {
            let result = PermissionHealthCheck.overallHealth(screenRecording: status, microphone: .healthy)
            XCTAssertTrue(result.isHealthy, "screen recording \(status) is not a reported problem")
            XCTAssertEqual(result.problems, [])
            for source in [RecordingSource.appAndMic(pid: 1), .appOnly(pid: 1), .micOnly] {
                XCTAssertNil(result.recordingRefusalReason(for: source), "\(status)/\(source)")
            }
        }
    }

    func testMicrophoneProblemDoesNotBlockAMicLessRecording() {
        let result = PermissionHealthCheck.overallHealth(screenRecording: .healthy, microphone: .denied)
        XCTAssertNotNil(result.recordingRefusalReason(for: .appAndMic(pid: 1)))
        // A no-mic recording captures app audio only, so it never asks for the grant.
        XCTAssertNil(result.recordingRefusalReason(for: .appOnly(pid: 1)))
    }

    func testRefusalReasonNamesOnlyBlockingProblems() throws {
        let result = PermissionHealthCheck.overallHealth(
            screenRecording: .healthy,
            microphone: .denied,
            accessibility: .denied,
        )
        let body = try XCTUnwrap(result.recordingRefusalReason(for: .appAndMic(pid: 1)))
        XCTAssertTrue(body.contains("Microphone"))
        XCTAssertFalse(body.contains("Accessibility"))
        // The aggregate body is untouched and still names both.
        XCTAssertTrue(result.notificationBody.contains("Microphone"))
        XCTAssertTrue(result.notificationBody.contains("Accessibility"))
    }

    func testRefusalReasonNeverNamesScreenRecording() throws {
        // A refusal used to name both grants. With the Screen Recording proxy
        // gone, a user who reads the refusal must not be sent to a pane that has
        // nothing to do with why the recording was refused.
        let result = PermissionHealthCheck.overallHealth(screenRecording: .denied, microphone: .denied)
        XCTAssertEqual(result.recordingBlockers(for: .appAndMic(pid: 1)), [.microphoneDenied])
        let reason = try XCTUnwrap(result.recordingRefusalReason(for: .appAndMic(pid: 1)))
        XCTAssertFalse(reason.contains("Screen Recording"))
        XCTAssertTrue(reason.contains("Microphone"))
    }

    func testHealthyBlocksNothing() {
        let result = PermissionHealthCheck.overallHealth(screenRecording: .healthy, microphone: .healthy)
        XCTAssertNil(result.recordingRefusalReason(for: .appAndMic(pid: 1)))
    }

    // MARK: - The full matrix

    /// Every (problem, source) cell spelled out, because the exhaustive switch
    /// in `blocksRecording` does not actually force a new permission to be
    /// classified: `HealthCheckResult.problems` is hand-written, so a status
    /// added there with no case reaching this switch compiles clean and
    /// silently blocks nothing. Only these assertions notice.
    func testBlockingMatrix() {
        let app = RecordingSource.appAndMic(pid: 1)
        let appOnly = RecordingSource.appOnly(pid: 1)
        let micOnly = RecordingSource.micOnly

        // The microphone grant blocks exactly the sources that record a mic.
        for problem in [PermissionProblem.microphoneDenied, .microphoneBroken] {
            XCTAssertTrue(problem.blocksRecording(for: app))
            XCTAssertFalse(problem.blocksRecording(for: appOnly))
            XCTAssertTrue(problem.blocksRecording(for: micOnly))
        }

        // Accessibility feeds participant names only, never a capture channel.
        for problem in [PermissionProblem.accessibilityDenied, .accessibilityBroken] {
            for source in [app, appOnly, micOnly] {
                XCTAssertFalse(problem.blocksRecording(for: source))
            }
        }
    }

    func testDeniedScreenRecordingDoesNotBlockAMicrophoneOnlyRecording() {
        // The behaviour issue #633 turned on, kept as a regression pin now that
        // the grant blocks nothing at all: a recording that opens no tap has
        // never had anything for this grant to stand in for.
        let result = PermissionHealthCheck.overallHealth(screenRecording: .denied, microphone: .healthy)

        XCTAssertNil(result.recordingRefusalReason(for: .micOnly))
    }

    func testDeniedMicrophoneBlocksAMicrophoneOnlyRecording() {
        // The other half, and the one that must not be lost while relaxing the
        // first: without the mic grant a mic-only recording captures nothing at
        // all, so it is the one source for which this grant is mandatory.
        let result = PermissionHealthCheck.overallHealth(screenRecording: .healthy, microphone: .denied)

        XCTAssertEqual(result.recordingBlockers(for: .micOnly), [.microphoneDenied])
        XCTAssertNotNil(result.recordingRefusalReason(for: .micOnly))
    }
}
