#if !APPSTORE
    import AppKit
    import Foundation
    import os.log

    private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "ChromeTabURLReader")

    /// Reads the addresses of Google Chrome's open tabs through its AppleScript
    /// dictionary, for `BrowserAutoRecordPolicy`.
    ///
    /// Runs `osascript` as a child process rather than `NSAppleScript`
    /// in-process, for one reason: a hard timeout. Apple Events to a browser
    /// showing a modal can block indefinitely, and `terminate()` on a child is
    /// the only way to be sure the watch loop gets its thread back. The TCC
    /// attribution is the same either way (the child's responsible process is
    /// this app), so the Automation prompt names Meeting Transcriber.
    ///
    /// Needs `NSAppleEventsUsageDescription` and the
    /// `com.apple.security.automation.apple-events` entitlement; the sandboxed
    /// App Store build has neither, which is why the whole file is compiled
    /// out there and only the calendar signal remains.
    enum ChromeTabURLReader {
        static let bundleIdentifier = "com.google.Chrome"

        /// One URL per line. Written out as loops rather than
        /// `URL of tabs of windows` so the output is flat and unambiguous
        /// whatever AppleScript's list-to-text coercion does.
        static let script = """
        tell application "Google Chrome"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (URL of t) & linefeed
                end repeat
            end repeat
            return out
        end tell
        """

        /// The open tab URLs, or `[]` when Chrome is not running, the script
        /// fails (Automation denied, dictionary changed), or `timeout` passes.
        ///
        /// The running-application check comes first and is load-bearing: a
        /// `tell application` to an app that is not running launches it.
        static func tabURLs(timeout: Duration = .seconds(3)) async -> [URL] {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
                return []
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                logger.error("osascript failed to launch: \(error.localizedDescription, privacy: .public)")
                return []
            }
            let handle = stdout.fileHandleForReading
            let output: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    var text = ""
                    do {
                        for try await line in handle.bytes.lines {
                            text += line + "\n"
                        }
                    } catch {
                        return nil
                    }
                    return text
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }
                // `next()` yields the child's `String?` wrapped once more;
                // flatten rather than `?? nil`, which the linter rejects.
                let first = await group.next().flatMap(\.self)
                group.cancelAll()
                return first
            }
            guard let output else {
                logger.warning("osascript did not answer within the timeout; terminating it")
                process.terminate()
                return []
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                // Automation denied reports here (-1743), as does a changed
                // scripting dictionary. Not an error for the user: the policy
                // simply has no tab signal and the calendar one still applies.
                logger.info("osascript exited with status \(process.terminationStatus, privacy: .public)")
            }
            return parse(output)
        }

        /// One URL per non-empty line, in order, without duplicates. Lines
        /// AppleScript emits for tabs with no address (`missing value`) are
        /// not URLs and fall out through the failed parse.
        static func parse(_ output: String) -> [URL] {
            var seen = Set<String>()
            return output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != "missing value" && seen.insert($0).inserted }
                .compactMap { URL(string: $0) }
        }
    }
#endif
