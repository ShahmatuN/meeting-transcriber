import Foundation

/// The browser tab-URL seam the auto-watch loop gets, resolved once per loop.
extension WatchingController {
    /// Production reads Chrome's tabs through `ChromeTabURLReader`; the App
    /// Store build has no Apple Events entitlement and answers "no tabs", so
    /// only the calendar signal can auto-record there.
    ///
    /// `MEETINGTRANSCRIBER_DEBUG_FAKE_TAB_URLS` (comma-separated, dev builds
    /// only) replaces the reader with a fixed answer. The browser e2e lane's
    /// fixture page is not Google Meet and the runner holds no Automation
    /// grant, so this is how `--auto-record` proves the loop skips the prompt
    /// without a real Meet tab; the real `osascript` path is manual QA.
    static func browserTabURLProvider() -> (String) async -> [URL] {
        #if APPSTORE
            return { _ in [] }
        #else
            if let raw = ProcessInfo.processInfo.environment["MEETINGTRANSCRIBER_DEBUG_FAKE_TAB_URLS"] {
                let fixed = raw.split(separator: ",").compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
                return { _ in fixed }
            }
            return { process in
                guard BrowserAutoRecordPolicy.supportedProcesses.contains(process) else { return [] }
                return await ChromeTabURLReader.tabURLs()
            }
        #endif
    }
}
