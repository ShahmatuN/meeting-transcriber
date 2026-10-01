import Foundation

/// Whether a browser meeting may start recording without the consent prompt.
///
/// The browser-meeting detector sees one thing: a Chromium browser holding a
/// WebRTC assertion. That is not meeting-exclusive, which is why browser
/// meetings prompt (issue #503). This policy adds the two signals that say
/// "this is a Google Meet call": a running calendar event carrying a
/// `meet.google.com` link, or an open `meet.google.com/<code>` tab in the
/// browser. Either one is enough; both come from outside the detector and are
/// gathered by `WatchLoop+AutoRecord` only when the policy could say yes.
///
/// Pure, and deliberately narrow: one browser, one meeting service, off by
/// default (`AppSettings.autoRecordGoogleMeet`). The deny list ("Never for
/// this app") is applied by the detector before anything reaches this, so a
/// refused browser never gets here.
///
/// Accepted trade-off, documented at the setting too: Chrome holds the WebRTC
/// assertion on the Meet lobby page as well, so a recording can start before
/// Join. The end-grace logic stops it when the user leaves, and a lobby-only
/// capture is a short `auto` recording a consumer can discard.
enum BrowserAutoRecordPolicy {
    /// The browsers this applies to, by the process name the power assertion
    /// reports. Chrome only: it is the browser the tab reader speaks to.
    static let supportedProcesses: Set<String> = ["Google Chrome"]

    enum Decision: Equatable {
        /// Fall through to the consent prompt, exactly as without the policy.
        case ask
        /// Record now, under this title.
        case autoRecord(title: String)
    }

    static func decide(
        enabled: Bool,
        processName: String,
        scheduled: ScheduledMeeting?,
        tabURLs: [URL],
    ) -> Decision {
        guard enabled, supportedProcesses.contains(processName) else { return .ask }
        // The calendar wins the title: an invitation names the meeting better
        // than a Meet code does, and it is the same title `handleMeeting`
        // would pick anyway.
        if let scheduled, scheduled.isGoogleMeet {
            return .autoRecord(title: scheduled.title)
        }
        if let code = tabURLs.lazy.compactMap(meetCode(in:)).first {
            return .autoRecord(title: "Google Meet \(code)")
        }
        return .ask
    }

    /// The meeting code of a Google Meet call URL, or nil for anything else on
    /// or off that host. `meet.google.com/abc-defg-hij` is a call;
    /// `meet.google.com/lookup/<alias>` is a call reached through a named
    /// alias; the landing page (`/`, `/landing`) and anything with more path
    /// is not a call and must not start a recording.
    static func meetCode(in url: URL) -> String? {
        guard url.host(percentEncoded: false)?.lowercased() == "meet.google.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch parts.count {
        case 1 where isMeetCode(parts[0]):
            return parts[0]
        case 2 where parts[0] == "lookup" && !parts[1].isEmpty:
            return parts[1]
        default:
            return nil
        }
    }

    /// `xxx-xxxx-xxx`, lowercase letters, which is the shape of every Meet
    /// call code.
    static func isMeetCode(_ candidate: String) -> Bool {
        candidate.wholeMatch(of: /[a-z]{3}-[a-z]{4}-[a-z]{3}/) != nil
    }
}
