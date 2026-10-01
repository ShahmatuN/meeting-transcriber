import AppKit
import ApplicationServices
import AudioTapLib
import AVFoundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "AdvancedSettingsView")

private enum PrivacyPane: String {
    case screenCapture = "Privacy_ScreenCapture"
    /// The "System Audio Recording Only" section of the combined pane on
    /// macOS 15+. Unverified that System Settings scrolls to the section
    /// rather than opening the pane; the pane is the right one either way.
    case audioCapture = "Privacy_AudioCapture"
    case microphone = "Privacy_Microphone"
    case accessibility = "Privacy_Accessibility"
    case calendars = "Privacy_Calendars"

    var url: String {
        "x-apple.systempreferences:com.apple.preference.security?\(rawValue)"
    }
}

struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings

    /// Seams for the two Screen Recording calls, so a test can render the row
    /// without a TCC probe and assert that the button is wired to the request.
    /// Production defaults are the real calls.
    var checkScreenRecording: () -> Bool = { Permissions.checkScreenRecording() }
    var requestScreenRecording: () -> Void = { Permissions.ensureScreenRecordingAccess() }
    /// Calendar access as `CalendarController` last read it; nil hides the row
    /// (a view rendered without an `AppState`). The grant is requested from
    /// Settings → General, where the feature it serves is switched on.
    var calendarAuthorization: CalendarAuthorization?

    @State private var micPermission: AVAuthorizationStatus = .notDetermined
    @State private var screenRecordingOK = false
    @State private var accessibilityOK = false
    @State private var lastExportFile: String?
    @State private var lastExportError: String?
    /// True while a `DiagnosticExporter.export` call is running off-main.
    /// Used to dim the button and surface a spinner so a 50-200 MB persistent
    /// log doesn't look like the app froze.
    @State private var isExportingDiagnostics = false

    var body: some View {
        // swiftlint:disable:next closure_body_length
        Form {
            permissionsSection

            // swiftlint:disable:next closure_body_length
            Section("Diagnostics") {
                Toggle("Verbose Diagnostic Logging", isOn: $settings.verboseDiagnostics)
                Text(
                    "Logs detailed diagnostics across recording, transcription,"
                        + " diarization, and protocol generation. Used to debug"
                        + " issues. Off by default — toggle on, reproduce the"
                        + " problem, then click \"Export Diagnostics…\" below to"
                        + " attach a redacted log file to a bug report.",
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Export Diagnostics…") { exportDiagnostics() }
                        .disabled(isExportingDiagnostics)
                    if isExportingDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let file = lastExportFile {
                    Text("Exported to: \(file)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let err = lastExportError {
                    Text("Export failed: \(err)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                #if !APPSTORE
                    Button("Open Diagnostic Logs Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([PersistentDiagnosticLog.logDirectory])
                    }
                    Text(
                        "Persistent logs are kept for 30 days at"
                            + " ~/Library/Logs/MeetingTranscriber/. Useful when"
                            + " you need to attach logs from a session that"
                            + " happened earlier today (or yesterday).",
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Toggle("Local Automation API", isOn: $settings.debugRPCEnabled)
                    Text(
                        "Exposes the local automation API + pipeline state on"
                            + " 127.0.0.1:9876 (POST /v1/transcribe, /v1/jobs, and"
                            + " /v1/watch to start/stop watching from a hotkey or"
                            + " Stream Deck; also `mt-cli`). Localhost-only,"
                            + " bearer-token auth. Off by default; enable for"
                            + " headless automation or shell-driven inspection.",
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshPermissions() }
    }

    /// Microphone first because it is the one grant that blocks a recording,
    /// then the tap's grant, then the two optional ones. Its own property so
    /// the `Form` body stays under the type-check budget.
    private var permissionsSection: some View {
        // swiftlint:disable:next closure_body_length
        Section("Permissions") {
            PermissionRow(
                label: "Microphone",
                detail: micPermission == .authorized ? "Granted"
                    : micPermission == .notDetermined ? "Will prompt on first recording"
                    : "Denied — click to open Settings",
                granted: micPermission == .authorized,
                warning: micPermission == .notDetermined,
                help: "System Settings → Privacy & Security → Microphone → enable Meeting Transcriber",
                settingsURL: PrivacyPane.microphone.url,
            )
            // The grant the app-audio tap runs on. macOS asks at the first
            // tap creation and offers no way to read the answer back, so the
            // row cannot show a status; what it can do is name the pane for a
            // user whose app-audio tracks came back silent.
            PermissionRow(
                label: "Audio Recording",
                detail: "Status cannot be read back — macOS asks on the first app-audio recording. "
                    + "If app-audio tracks are silent from the start, enable it here",
                granted: false,
                unknown: true,
                help: "\(SystemSettingsPaths.audioRecording) → enable Meeting Transcriber",
                settingsURL: PrivacyPane.audioCapture.url,
            )
            PermissionRow(
                label: "Screen Recording",
                detail: "Optional — improves meeting titles (window names). Not needed for detection or audio capture",
                granted: screenRecordingOK,
                optional: true,
                help: "\(SystemSettingsPaths.screenRecording) → enable Meeting Transcriber",
                settingsURL: PrivacyPane.screenCapture.url,
            )
            if !screenRecordingOK {
                // Asking is what registers the app in the pane at all;
                // preflighting never does, so without this the "Open System
                // Settings" link above lands on a list the app is absent from.
                // The request happens here and nowhere else (not at watch
                // start): the grant is optional, so the ask belongs where the
                // user has just read what it buys.
                Button("Request Access…") {
                    requestScreenRecording()
                }
                .font(.caption)
                .accessibilityIdentifier(A11yID.screenRecordingRequestButton)
            }
            PermissionRow(
                label: "Accessibility",
                detail: "Optional — reads Teams participant names for speaker suggestions",
                granted: accessibilityOK,
                optional: true,
                help: "System Settings → Privacy & Security → Accessibility → enable Meeting Transcriber",
                settingsURL: PrivacyPane.accessibility.url,
            )
            if let calendarAuthorization {
                PermissionRow(
                    label: "Calendars",
                    detail: "Optional — names recordings after the running calendar event (Settings → General)",
                    granted: calendarAuthorization == .fullAccess,
                    optional: true,
                    help: "System Settings → Privacy & Security → Calendars → Meeting Transcriber → Full Access",
                    settingsURL: PrivacyPane.calendars.url,
                )
            }

            Button("Refresh") {
                refreshPermissions()
            }
            .font(.caption)
        }
    }

    private func refreshPermissions() {
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        screenRecordingOK = checkScreenRecording()
        accessibilityOK = AXIsProcessTrusted()
    }

    private func exportDiagnostics() {
        guard !isExportingDiagnostics else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingTranscriber-diagnostics-\(stamp).log")
        let info = DiagnosticExporter.HeaderInfo(
            appVersion: Bundle.main.appVersion,
            commit: Bundle.main.gitCommitHash,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            settings: [
                "verboseDiagnostics": "\(settings.verboseDiagnostics)",
                "diarize": "\(settings.diarize)",
                "vadEnabled": "\(settings.vadEnabled)",
                "transcriptionEngine": settings.transcriptionEngine.rawValue,
                "protocolProvider": settings.protocolProvider.rawValue,
                "recordOnly": "\(settings.recordOnly)",
            ],
        )

        isExportingDiagnostics = true
        // The persistent-log file source can be 50-200 MB and reads via
        // `String(contentsOf:)` + `split(separator:)` — and the OSLogStore
        // fallback's `getEntries` is famously slow on the main actor. Detach
        // so the Settings UI stays responsive while the export runs.
        Task.detached(priority: .userInitiated) {
            let result = Result { try DiagnosticExporter.export(to: outURL, info: info) }
            await MainActor.run {
                isExportingDiagnostics = false
                switch result {
                case let .success(count):
                    lastExportFile = outURL.lastPathComponent
                    lastExportError = nil
                    NSWorkspace.shared.activateFileViewerSelecting([outURL])
                    let exportedFile = outURL.lastPathComponent
                    logger.info(
                        "diagnostics_exported lines=\(count, privacy: .public) file=\(exportedFile, privacy: .public)",
                    )

                case let .failure(error):
                    lastExportFile = nil
                    lastExportError = error.localizedDescription
                    logger.error(
                        "diagnostics_export_failed error=\(error.localizedDescription, privacy: .public)",
                    )
                }
            }
        }
    }
}
