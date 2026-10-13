#if !APPSTORE
    @testable import MeetingTranscriber
    import XCTest

    final class PostJobHookTests: XCTestCase {
        // swiftlint:disable:next implicitly_unwrapped_optional
        private var tmpDir: URL!

        override func setUp() async throws {
            try await super.setUp()
            tmpDir = try makeTempDirectory(prefix: "PostJobHookTests")
        }

        override func tearDown() async throws {
            if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
            try await super.tearDown()
        }

        private func makeRunner(timeout: Duration = .seconds(30)) -> PostJobHookRunner {
            PostJobHookRunner(shell: "/bin/sh", timeout: timeout, logURL: tmpDir.appendingPathComponent("hook.log"))
        }

        // MARK: - Environment

        func testEnvironmentDescribesTheJob() throws {
            var job = PipelineJob(
                meetingTitle: "Maksim / Evgeniy", appName: "Google Chrome",
                mixPath: nil, appPath: nil, micPath: nil, micDelay: 0,
                participants: ["k.markidonov", "Ирина Разумова"],
                meetingStartTime: Date(timeIntervalSince1970: 1_791_878_400), // 2026-10-13 08:00 UTC
            )
            job.transcriptPath = URL(fileURLWithPath: "/tmp/out/t.txt")
            let env = try XCTUnwrap(PostJobHook.environment(for: job, timeZone: XCTUnwrap(TimeZone(identifier: "UTC"))))

            XCTAssertEqual(env["MT_TRANSCRIPT"], "/tmp/out/t.txt")
            XCTAssertNil(env["MT_PROTOCOL"])
            XCTAssertEqual(env["MT_TITLE"], "Maksim / Evgeniy")
            XCTAssertEqual(env["MT_APP"], "Google Chrome")
            XCTAssertEqual(env["MT_DATE"], "2026-10-13")
            XCTAssertEqual(env["MT_START"], "08:00")
            XCTAssertEqual(env["MT_PARTICIPANTS"], "k.markidonov\nИрина Разумова")
            XCTAssertEqual(env["MT_JOB_ID"], job.id.uuidString)
        }

        func testNothingToHandOverMeansNoRun() {
            let job = PipelineJob(
                meetingTitle: "Gone", appName: "Teams",
                mixPath: nil, appPath: nil, micPath: nil, micDelay: 0,
            )
            XCTAssertNil(PostJobHook.environment(for: job))
        }

        func testSummaryIsTheLastNonEmptyLine() {
            XCTAssertEqual(PostJobHook.summaryLine(of: "Saved raw/x.md\nИТОГ: 2 cards\n\n  \n"), "ИТОГ: 2 cards")
            XCTAssertNil(PostJobHook.summaryLine(of: "\n \n"))
        }

        // MARK: - Runner

        func testSuccessReportsTheLastOutputLineAndLogs() async throws {
            let outcome = await makeRunner().run(command: "echo first; echo \"$MT_TITLE\"", environment: ["MT_TITLE": "Sync"])
            XCTAssertEqual(outcome, .succeeded(summary: "Sync"))
            let log = try String(contentsOf: tmpDir.appendingPathComponent("hook.log"), encoding: .utf8)
            XCTAssertTrue(log.contains("first"), log)
        }

        func testNonZeroExitIsAFailureWithItsStatus() async {
            let outcome = await makeRunner().run(command: "echo nope; exit 3", environment: [:])
            XCTAssertEqual(outcome, .failed(status: 3, summary: "nope"))
        }

        func testACommandPastTheTimeoutIsStopped() async {
            let outcome = await makeRunner(timeout: .milliseconds(300)).run(command: "sleep 10", environment: [:])
            XCTAssertEqual(outcome, .timedOut)
        }

        /// Two meetings finishing together must not run their commands at once.
        func testCommandsRunOneAtATime() async throws {
            let runner = makeRunner()
            let file = tmpDir.appendingPathComponent("order.txt").path
            let command = "echo \"$TAG\" >> '\(file)'; sleep 0.3; echo \"$TAG\" >> '\(file)'"
            async let first = runner.run(command: command, environment: ["TAG": "A"])
            async let second = runner.run(command: command, environment: ["TAG": "B"])
            _ = await (first, second)

            let lines = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n")
            XCTAssertEqual(lines.count, 4)
            XCTAssertEqual(lines[0], lines[1], "interleaved: \(lines)")
            XCTAssertEqual(lines[2], lines[3], "interleaved: \(lines)")
        }
    }
#endif
