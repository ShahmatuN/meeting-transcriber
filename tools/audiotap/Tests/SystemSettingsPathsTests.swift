@testable import AudioTapLib
import XCTest

/// The pane name is version-dependent (macOS 15 renamed "Screen Recording" to
/// "Screen & System Audio Recording") and shared by the tap-error hint, the
/// permission UI, and the channel-health notification, so it is worth pinning.
final class SystemSettingsPathsTests: XCTestCase {
    func testScreenRecordingPathUsesSequoiaPaneName() {
        XCTAssertEqual(
            SystemSettingsPaths.screenRecordingPath(sequoiaOrLater: true),
            "System Settings → Privacy & Security → Screen & System Audio Recording",
        )
    }

    func testScreenRecordingPathUsesLegacyPaneNameBeforeSequoia() {
        XCTAssertEqual(
            SystemSettingsPaths.screenRecordingPath(sequoiaOrLater: false),
            "System Settings → Privacy & Security → Screen Recording",
        )
    }

    func testScreenRecordingResolvesToAKnownPane() {
        // The OS-resolved value must match one of the two version branches.
        let resolved = SystemSettingsPaths.screenRecording
        XCTAssertTrue(
            resolved == SystemSettingsPaths.screenRecordingPath(sequoiaOrLater: true)
                || resolved == SystemSettingsPaths.screenRecordingPath(sequoiaOrLater: false),
        )
    }

    func testAudioRecordingPathNamesTheAudioOnlySectionOnSequoia() {
        // The grant the process tap runs on. On 15+ it is a section of the
        // combined pane, so the path goes one level deeper than
        // `screenRecording`; a user sent to the pane alone looks for the app
        // in the screen-capture list and does not find it there.
        XCTAssertEqual(
            SystemSettingsPaths.audioRecordingPath(sequoiaOrLater: true),
            "System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only",
        )
    }

    func testAudioRecordingPathFallsBackToTheScreenRecordingPaneBeforeSequoia() {
        XCTAssertEqual(
            SystemSettingsPaths.audioRecordingPath(sequoiaOrLater: false),
            SystemSettingsPaths.screenRecordingPath(sequoiaOrLater: false),
        )
    }

    func testAudioRecordingResolvesToAKnownPane() {
        let resolved = SystemSettingsPaths.audioRecording
        XCTAssertTrue(
            resolved == SystemSettingsPaths.audioRecordingPath(sequoiaOrLater: true)
                || resolved == SystemSettingsPaths.audioRecordingPath(sequoiaOrLater: false),
        )
    }

    func testSoundOutputNamesThePaneThatChangesTheOutputDevice() {
        // Not version-dependent the way the recording pane is: Ventura through
        // macOS 26 all keep Output inside the Sound pane, and the app's floor is
        // macOS 14.2.
        XCTAssertEqual(SystemSettingsPaths.soundOutput, "System Settings → Sound → Output")
    }
}
