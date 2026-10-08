import AppKit
import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    /// Latest notification visibility from `PermissionsController`, or nil
    /// before the first check. Browser-meeting recording depends on it (the
    /// consent prompt is a notification), and nothing else in the app can say so
    /// without using the channel that is broken.
    var notificationVisibility: NotificationVisibility?

    /// Calendar concern behind the Calendar section. Nil hides the section,
    /// which is the state of a view rendered without an `AppState` (tests).
    var calendar: CalendarController?

    /// Nil until the first permission check. The case, not just the message:
    /// how total the failure is decides the headline.
    private var browserConsentReadiness: BrowserConsentReadiness? {
        guard let notificationVisibility else { return nil }
        return BrowserConsentReadiness.evaluate(
            browserMeetingsEnabled: settings.watchBrowserMeetings,
            visibility: notificationVisibility,
        )
    }

    var body: some View {
        // swiftlint:disable:next closure_body_length
        Form {
            Section("Mode") {
                Toggle("Record-only mode", isOn: $settings.recordOnly)
                    .accessibilityIdentifier(A11yID.recordOnlyToggle)
                if settings.recordOnly {
                    recordOnlyBanner
                }
            }

            Section("Apps to Watch") {
                Toggle("Microsoft Teams", isOn: $settings.watchTeams)
                Toggle("Zoom", isOn: $settings.watchZoom)
                Toggle("Webex", isOn: $settings.watchWebex)
                Toggle("WeChat", isOn: $settings.watchWeChat)
                Toggle("Tencent Meeting", isOn: $settings.watchTencentMeeting)
                Toggle("FaceTime", isOn: $settings.watchFaceTime)
                Toggle("WhatsApp", isOn: $settings.watchWhatsApp)
                Toggle("Browser Web Meetings", isOn: $settings.watchBrowserMeetings)
                    .accessibilityIdentifier(A11yID.watchBrowserToggle)
                Text(
                    """
                    Detects web meetings (Google Meet, Whereby, web Zoom/Teams) by the WebRTC \
                    signal, so any browser works. Other apps that place calls can trigger it too; \
                    it asks before recording (unless auto-record below applies), and \
                    "Never for this app" stops one for good.
                    """,
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                autoRecordGoogleMeet
                browserConsentWarning
                consentDenyList
            }

            if let calendar {
                CalendarSettingsSection(settings: settings, calendar: calendar)
            }

            Section("Detection") {
                HStack {
                    Text("Poll Interval")
                    Spacer()
                    TextField("", value: $settings.pollInterval, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.pollInterval, in: 1 ... 30, step: 0.5)
                        .labelsHidden()
                    Text("seconds").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Grace Period")
                    Spacer()
                    TextField("", value: $settings.endGrace, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.endGrace, in: 1 ... 120, step: 1)
                        .labelsHidden()
                    Text("seconds").foregroundStyle(.secondary)
                }

                minimumAutoRecordingRow
            }
        }
        .formStyle(.grouped)
    }

    /// The false-trigger threshold. A detector can fire on a lobby page or a
    /// voice message, and the grace period ends such a capture after seconds;
    /// below this length an automatic recording is dropped rather than
    /// transcribed and offered for speaker naming.
    private var minimumAutoRecordingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Discard Auto Recordings Shorter Than")
                Spacer()
                TextField("", value: $settings.minimumAutoRecordingSeconds, format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $settings.minimumAutoRecordingSeconds, in: 0 ... 600, step: 10)
                    .labelsHidden()
                    .accessibilityIdentifier(A11yID.minimumAutoRecordingStepper)
                Text("seconds").foregroundStyle(.secondary)
            }
            Text("A capture this short is a false trigger, not a meeting. 0 keeps everything; manual recordings are always kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The one browser meeting that may skip the prompt. Nested under the
    /// browser toggle and disabled without it, because it is a refinement of
    /// that detection, not a detector of its own.
    private var autoRecordGoogleMeet: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Auto-record Google Meet in Chrome", isOn: $settings.autoRecordGoogleMeet)
                .accessibilityIdentifier(A11yID.autoRecordGoogleMeetToggle)
                .disabled(!settings.watchBrowserMeetings)
                .onChange(of: settings.autoRecordGoogleMeet) { _, enabled in
                    if enabled { Self.probeChromeTabs() }
                }
            Text(Self.autoRecordCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    #if APPSTORE
        private static let autoRecordCaption = """
        Starts recording without asking when a calendar event with a Google Meet link is running \
        while Chrome holds a call (Settings → General → Calendar). Recording may begin on the Meet \
        lobby page and stops when you leave.
        """

        private static func probeChromeTabs() {}
    #else
        private static let autoRecordCaption = """
        Starts recording without asking when Chrome has a meet.google.com call open, or a calendar \
        event with a Google Meet link is running (Settings → General → Calendar). The first time, \
        macOS asks to let Meeting Transcriber control Google Chrome, which is how the tab addresses \
        are read. Recording may begin on the Meet lobby page and stops when you leave.
        """

        /// Ask Chrome once, right now, so the Automation prompt appears while the
        /// user is looking at the switch that needs it, not mid-meeting. The
        /// result is discarded; the prompt is the point.
        private static func probeChromeTabs() {
            Task { _ = await ChromeTabURLReader.tabURLs() }
        }
    #endif

    /// Apps the user answered "Never for this app" about.
    ///
    /// Shown whenever the list is non-empty, deliberately NOT gated on the
    /// browser toggle. Today only browser meetings ask for consent, but the
    /// gate it hangs off is `requiresRecordingConsent`, a general pattern
    /// property, and the moment another app adopts it a denial made there would
    /// become impossible to undo behind a browser-specific switch. An empty
    /// list stays hidden: the only reason to come here is to take back a Never.
    ///
    /// Writes go through `ConsentDenyListStore`, the same path the consent gate
    /// uses, so list semantics live in one place instead of two.
    @ViewBuilder private var consentDenyList: some View {
        if !settings.consentDeniedApps.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Never record these apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(settings.consentDeniedApps.enumerated()), id: \.element) { index, app in
                    HStack {
                        Text(app)
                            .font(.caption)
                        Spacer()
                        Button("Remove") {
                            ConsentDenyListStore(settings: settings).revert(app)
                        }
                        .accessibilityIdentifier(A11yID.consentDeniedAppRemove(index))
                    }
                }
            }
            .accessibilityIdentifier(A11yID.consentDenyListSection)
        }
    }

    /// Warns when browser watching is on but the consent prompt cannot reach the
    /// user. Rendered here rather than as a notification for the obvious reason,
    /// and kept out of the menu-bar permission badge because this permission only
    /// matters for this one opt-in feature.
    @ViewBuilder private var browserConsentWarning: some View {
        if let readiness = browserConsentReadiness,
           let headline = readiness.headline,
           let warning = readiness.warning {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.callout.weight(.semibold))
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(A11yID.browserConsentWarning)
                    Button("Open Notification Settings") {
                        NSWorkspace.shared.open(Self.notificationSettingsURL)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .padding(8)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Deep link to System Settings > Notifications. Verified to land on the
    /// Notifications pane rather than merely opening the app.
    private static let notificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.notifications",
    )!

    private var recordOnlyBanner: some View {
        let display = OutputSettingsLogic.displayPath(
            for: settings.effectiveOutputDir.appendingPathComponent("recordings"),
            home: FileManager.default.homeDirectoryForCurrentUser,
        )
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Record-only mode is active.")
                    .font(.callout.weight(.semibold))
                Text(
                    "Files land in `\(display)`. Each recording gets a `<timestamp>_meta.json` " +
                        "sidecar next to its WAVs. No transcription, diarization, or protocol " +
                        "generation runs on this device.",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier(A11yID.recordOnlyBanner)
    }
}
