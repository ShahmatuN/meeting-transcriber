import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "WatchLoop")

/// The false-trigger threshold at the end of a recording (`ShortRecordingPolicy`,
/// `AppSettings.minimumAutoRecordingSeconds`). Its own file like the other
/// `WatchLoop+*` concerns, and because `WatchLoop.swift` is at the length cap.
extension WatchLoop {
    /// Judge a finished recording and, when it is a false trigger, drop it:
    /// the files go, because anything left in the staging directory is picked
    /// up again as an orphan on the next launch, and the user is told once, as
    /// a plain banner, because a recording that never was is nothing to act
    /// on. Returns true when the recording was dropped and must not be
    /// enqueued. The record-only path never reaches here: it writes the
    /// sidecar with its `trigger` and leaves the policy to the consumer, as
    /// that format promises.
    ///
    /// The length is measured on the loop's own clock, from the instant the
    /// phase went to `.recording`: the recorder's start date is the real wall
    /// clock, which a test clock cannot move.
    func discardIfShort(
        _ recording: RecordingResult, trigger: RecordingSidecar.Trigger, appName: String,
    ) -> Bool {
        let duration = nowProvider().timeIntervalSince(recordingStartedAt ?? recording.recordingStartDate)
        let minimum = minimumAutoRecordingSeconds()
        guard ShortRecordingPolicy.discards(trigger: trigger, duration: duration, minimum: minimum) else {
            return false
        }
        for url in [recording.mixPath, recording.appPath, recording.micPath].compactMap(\.self) {
            try? FileManager.default.removeItem(at: url)
        }
        logger.info(
            "Discarded a \(Int(duration), privacy: .public) s automatic recording of \(appName, privacy: .public): below the \(Int(minimum), privacy: .public) s minimum",
        )
        notifier.notify(
            title: "Short Recording Discarded",
            body: "\(appName): \(Int(duration)) s, below the \(Int(minimum)) s minimum for automatic recordings (Settings → General).",
            urgency: .standard,
        )
        return true
    }
}
