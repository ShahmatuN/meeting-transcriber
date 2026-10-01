import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "WatchLoopAutoRecord")

/// The browser auto-record branch of the poll loop, in front of the consent
/// gate (`WatchLoop+Consent`). Split out of `WatchLoop.swift` for the line
/// cap; an extension of the `@MainActor` class inherits its isolation.
///
/// Lives at the loop level rather than in the detector because its two
/// inputs are side effects: a calendar read and an Apple Event to Chrome,
/// the latter with a timeout. The detector's identity synthesis stays pure
/// and keeps carrying `requiresRecordingConsent`, so a browser meeting that
/// this branch declines is prompted for exactly as before.
extension WatchLoop {
    /// The title to record this meeting under right now, or nil to fall
    /// through to the consent path.
    ///
    /// Returns nil without gathering anything unless the meeting is one that
    /// would otherwise prompt, the setting is on, no prompt is already parked
    /// and no decline cooldown is running: a tab read per poll while a prompt
    /// sits on screen, or while the user just said no, would be an Apple
    /// Event every few seconds for a question that is already answered.
    func autoRecordTitle(for meeting: DetectedMeeting) async -> String? {
        guard meeting.pattern.requiresRecordingConsent, autoRecordEnabled(), pendingConsentApp == nil else {
            return nil
        }
        let app = meeting.pattern.appName
        guard case .ask = consentPolicy.decision(
            app: app, now: nowProvider(), isDenied: denyListStore.isDenied(app),
        ) else { return nil }

        let scheduled = scheduledMeeting(nowProvider())
        let tabURLs = await browserTabURLs(app)
        let decision = BrowserAutoRecordPolicy.decide(
            enabled: true, processName: app, scheduled: scheduled, tabURLs: tabURLs,
        )
        guard case let .autoRecord(title) = decision else { return nil }
        // One literal: `Logger` takes an `OSLogMessage`, which is built from a
        // string literal with interpolations and cannot be concatenated.
        let fromCalendar = scheduled?.isGoogleMeet == true
        logger.info("Auto-recording Google Meet in \(app, privacy: .public): calendar=\(fromCalendar) tabs=\(tabURLs.count)")
        return title
    }
}
