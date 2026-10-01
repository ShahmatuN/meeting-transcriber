import CoreGraphics
import Foundation

/// Represents a detected active meeting.
struct DetectedMeeting: Equatable {
    let pattern: AppMeetingPattern
    let windowTitle: String
    let ownerName: String
    let windowPID: pid_t
    let detectedAt: Date

    init(
        pattern: AppMeetingPattern,
        windowTitle: String,
        ownerName: String,
        windowPID: pid_t,
        detectedAt: Date = Date(),
    ) {
        self.pattern = pattern
        self.windowTitle = windowTitle
        self.ownerName = ownerName
        self.windowPID = windowPID
        self.detectedAt = detectedAt
    }

    /// The same meeting under another title. Used when a signal outside the
    /// detector (a calendar event, a Meet code) names the call better than
    /// the window did; everything that identifies the meeting is kept.
    func retitled(_ title: String) -> Self {
        Self(
            pattern: pattern, windowTitle: title, ownerName: ownerName,
            windowPID: windowPID, detectedAt: detectedAt,
        )
    }
}

/// Protocol for meeting detection strategies.
protocol MeetingDetecting {
    /// Single poll: check for active meetings. Returns a meeting after confirmation threshold.
    func checkOnce() -> DetectedMeeting?

    /// Check if a previously detected meeting is still active.
    func isMeetingActive(_ meeting: DetectedMeeting) -> Bool

    /// Reset confirmation counters and start cooldown for the given app.
    func reset(appName: String?)
}

extension MeetingDetecting {
    // swiftlint:disable:next unused_declaration
    func reset() {
        reset(appName: nil)
    }
}
