import Foundation

/// User-facing macOS System Settings navigation paths, kept in one place so the
/// tap-error hint, the permission UI, and the channel-health notification all
/// name the pane identically. macOS 15 (Sequoia) renamed the "Screen Recording"
/// pane to "Screen & System Audio Recording"; the app supports macOS 14.2+, so
/// the correct label depends on the running OS.
public enum SystemSettingsPaths {
    private static var sequoiaOrLater: Bool {
        if #available(macOS 15, *) {
            true
        } else {
            false
        }
    }

    /// Path to the Screen Recording grant. For this app that grant is optional:
    /// it improves meeting titles (window names) and nothing else, so no
    /// capture-failure message should send a user here. The tap's own grant is
    /// ``audioRecording``. Callers add their own lead-in / trailing action text.
    public static var screenRecording: String {
        screenRecordingPath(sequoiaOrLater: sequoiaOrLater)
    }

    /// Path to the "Audio Recording" grant the CATapDescription process tap
    /// runs on (`NSAudioCaptureUsageDescription`). macOS prompts for it at the
    /// first tap creation; a tap that was refused returns `noErr` and delivers
    /// zeroes (issue #524), and there is no API to read the grant back, so this
    /// is the path the silent-track message and the tap-error hint name.
    ///
    /// On macOS 15+ the grants live in a "System Audio Recording Only" section
    /// of the combined Screen & System Audio Recording pane. On macOS 14 the
    /// audio-only grants list under the Screen Recording pane; that wording is
    /// from Apple's documentation, not measured on a 14.x machine.
    public static var audioRecording: String {
        audioRecordingPath(sequoiaOrLater: sequoiaOrLater)
    }

    /// Path to the pane that changes which device the system plays through.
    ///
    /// Named in the app-audio fault messages because switching the system
    /// output device is the one thing that rebuilds the tap, and a user told to
    /// switch it reaches for the picker in front of them, which during a call is
    /// the meeting app's own. That one cannot work: the rebuild is triggered by
    /// a change of the *system* default output device, which an output chosen
    /// inside another app does not touch.
    ///
    /// Unlike ``screenRecording`` this needs no OS branch. Output has lived
    /// inside the Sound pane since Ventura, and the app's floor is macOS 14.2.
    public static let soundOutput = "System Settings → Sound → Output"

    /// Pure form of ``screenRecording`` so both OS branches are unit-testable
    /// without faking the running OS version.
    static func screenRecordingPath(sequoiaOrLater: Bool) -> String {
        let pane = sequoiaOrLater ? "Screen & System Audio Recording" : "Screen Recording"
        return "System Settings → Privacy & Security → \(pane)"
    }

    /// Pure form of ``audioRecording``.
    static func audioRecordingPath(sequoiaOrLater: Bool) -> String {
        let pane = screenRecordingPath(sequoiaOrLater: sequoiaOrLater)
        return sequoiaOrLater ? "\(pane) → System Audio Recording Only" : pane
    }
}
