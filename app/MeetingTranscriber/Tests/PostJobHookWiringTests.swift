#if !APPSTORE
    @testable import MeetingTranscriber
    import XCTest

    // MARK: - Controller wiring

    private actor FakeHookRunner: PostJobHookRunning {
        struct Call {
            let command: String
            let environment: [String: String]
        }

        private(set) var calls: [Call] = []

        // swiftlint:disable:next async_without_await
        func run(command: String, environment: [String: String]) async -> PostJobHookOutcome {
            calls.append(Call(command: command, environment: environment))
            return .succeeded(summary: "ИТОГ: done")
        }
    }

    @MainActor
    final class PostJobHookWiringTests: XCTestCase {
        // swiftlint:disable:next implicitly_unwrapped_optional
        private var tmpDir: URL!
        // swiftlint:disable:next implicitly_unwrapped_optional
        private var suiteName: String!

        override func setUp() async throws {
            try await super.setUp()
            tmpDir = try makeTempDirectory(prefix: "PostJobHookWiringTests")
            suiteName = "PostJobHookWiringTests-\(getpid())-\(UUID().uuidString)"
        }

        override func tearDown() async throws {
            if let suiteName { DefaultsSuite.remove(suiteName) }
            if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
            try await super.tearDown()
        }

        private func finishJob(command: String) throws -> (FakeHookRunner, RecordingNotifier) {
            let settings = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
            settings.postJobCommand = command
            let notifier = RecordingNotifier()
            let pc = PipelineController(settings: settings, notifier: notifier)
            pc.queue = PipelineQueue(logDir: tmpDir)
            let hook = FakeHookRunner()
            pc.postJobHook = hook
            pc.configureCallbacks()

            var job = PipelineJob(
                meetingTitle: "Sync", appName: "Teams",
                mixPath: nil, appPath: nil, micPath: nil, micDelay: 0,
            )
            job.transcriptPath = tmpDir.appendingPathComponent("t.txt")
            pc.queue.insertJobForTesting(job)
            pc.queue.updateJobState(id: job.id, to: .done)
            return (hook, notifier)
        }

        func testFinishedJobRunsTheCommandAndReportsIt() async throws {
            let (hook, notifier) = try finishJob(command: "/x/to-wiki.py")
            let deadline = Date().addingTimeInterval(5)
            while notifier.calls.count < 2, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let calls = await hook.calls
            XCTAssertEqual(calls.map(\.command), ["/x/to-wiki.py"])
            XCTAssertEqual(calls.first?.environment["MT_TRANSCRIPT"], tmpDir.appendingPathComponent("t.txt").path)
            XCTAssertEqual(notifier.calls.last?.title, "After-meeting command finished")
            XCTAssertEqual(notifier.calls.last?.body, "ИТОГ: done")
        }

        func testNoCommandRunsNothing() async throws {
            let (hook, notifier) = try finishJob(command: "  ")
            try await Task.sleep(for: .milliseconds(100))
            let calls = await hook.calls
            XCTAssertTrue(calls.isEmpty)
            XCTAssertEqual(notifier.calls.map(\.title), ["Transcript Saved"])
        }
    }
#endif
