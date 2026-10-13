#if !APPSTORE
    import Foundation
    import os.log

    private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "PostJobHook")

    /// A shell command the user wants run after every finished meeting
    /// (`AppSettings.postJobCommand`, Settings → Output), e.g. a script that
    /// files the transcript into a notes folder. Homebrew build only: the
    /// sandbox forbids `Process`.
    ///
    /// The job is described to the command through environment variables, not
    /// arguments, so the command line the user types stays a plain shell line
    /// and a title with quotes or spaces cannot break it.
    enum PostJobHook {
        /// Long enough for a headless LLM pass over an hour's transcript; a
        /// command still running after this is terminated and reported.
        static let timeout: Duration = .seconds(30 * 60)

        /// Where every run's stdout and stderr go, owner-only.
        static var logURL: URL {
            AppPaths.dataDir.appendingPathComponent("post_job_hook.log")
        }

        /// The variables a command receives, or nil when the job left nothing
        /// to hand over (no transcript and no protocol on disk).
        ///
        /// `MT_PARTICIPANTS` is one name per line, because a display name can
        /// contain a comma. `MT_DATE`/`MT_START` are the meeting's start when
        /// it was recorded, else when the job was enqueued.
        static func environment(
            for job: PipelineJob,
            timeZone: TimeZone = .current,
        ) -> [String: String]? { // swiftlint:disable:this discouraged_optional_collection
            guard job.transcriptPath != nil || job.protocolPath != nil else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: job.artifactStartTime)
            var env: [String: String] = [
                "MT_JOB_ID": job.id.uuidString,
                "MT_TITLE": job.meetingTitle,
                "MT_APP": job.appName,
                "MT_DATE": String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                "MT_START": String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0),
                "MT_PARTICIPANTS": job.participants.joined(separator: "\n"),
            ]
            env["MT_TRANSCRIPT"] = job.transcriptPath?.path
            env["MT_PROTOCOL"] = job.protocolPath?.path
            return env
        }

        /// The last non-empty line of a command's stdout: what the command
        /// wants the user to see in the notification.
        static func summaryLine(of output: String) -> String? {
            output.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty }
                .map { String($0.prefix(200)) }
        }
    }

    enum PostJobHookOutcome: Equatable {
        case succeeded(summary: String?)
        case failed(status: Int32, summary: String?)
        case timedOut
        case couldNotStart(String)
    }

    protocol PostJobHookRunning: Sendable {
        func run(command: String, environment: [String: String]) async -> PostJobHookOutcome
    }

    /// Runs hook commands one at a time, in the order the jobs finished: two
    /// meetings ending together must not have two commands editing the same
    /// notes folder at once.
    actor PostJobHookRunner: PostJobHookRunning {
        private let shell: String
        private let timeout: Duration
        private let logURL: URL
        private var tail: Task<PostJobHookOutcome, Never>?

        init(shell: String = "/bin/zsh", timeout: Duration = PostJobHook.timeout, logURL: URL = PostJobHook.logURL) {
            self.shell = shell
            self.timeout = timeout
            self.logURL = logURL
        }

        func run(command: String, environment: [String: String]) async -> PostJobHookOutcome {
            let previous = tail
            let next = Task { [shell, timeout, logURL] in
                _ = await previous?.value
                return await Self.execute(
                    command: command, environment: environment,
                    shell: shell, timeout: timeout, logURL: logURL,
                )
            }
            tail = next
            return await next.value
        }

        /// A login shell (`-l`), so the command finds what the user's own
        /// terminal finds: an app launched by launchd starts with a bare PATH.
        private static func execute(
            command: String, environment: [String: String],
            shell: String, timeout: Duration, logURL: URL,
        ) async -> PostJobHookOutcome {
            let fm = FileManager.default
            let stdoutURL = fm.temporaryDirectory.appendingPathComponent("mt-hook-\(UUID().uuidString).out")
            guard fm.createFile(atPath: stdoutURL.path, contents: nil),
                  let stdout = try? FileHandle(forWritingTo: stdoutURL)
            else { return .couldNotStart("could not create an output file") }
            defer { try? fm.removeItem(at: stdoutURL) }
            let log = openLog(at: logURL)
            log?.write(Data("\n=== \(Date().ISO8601Format()) \(environment["MT_TITLE"] ?? "")\n".utf8))

            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lc", command]
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, hook in hook }
            process.standardOutput = stdout
            process.standardError = log ?? FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            let exited = AsyncStream<Void>.makeStream()
            process.terminationHandler = { _ in exited.continuation.yield() }
            do {
                try process.run()
            } catch {
                try? stdout.close()
                try? log?.close()
                logger.error("Post-job command could not start: \(error.localizedDescription, privacy: .public)")
                return .couldNotStart(error.localizedDescription)
            }
            let watchdog = Task { () -> Bool in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, process.isRunning else { return false }
                process.terminate()
                return true
            }
            for await _ in exited.stream {
                break
            }
            watchdog.cancel()
            let timedOut = await watchdog.value
            try? stdout.close()

            let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
            log?.write(Data(output.utf8))
            try? log?.close()
            let summary = PostJobHook.summaryLine(of: output)
            let status = process.terminationStatus
            logger.info("Post-job command exited status=\(status, privacy: .public)")
            if timedOut { return .timedOut }
            return status == 0 ? .succeeded(summary: summary) : .failed(status: status, summary: summary)
        }

        /// Appends to the log, starting it over once it passes a megabyte.
        private static func openLog(at url: URL) -> FileHandle? {
            let fm = FileManager.default
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > 1_000_000 || !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: url.path, contents: nil)
                try? fm.restrictToOwner(url)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
            _ = try? handle.seekToEnd()
            return handle
        }
    }
#endif
