import AppKit
import SwiftUI

/// Settings → General → Calendar: the integration switch, the access state,
/// and the per-calendar checklist. Its own view so `GeneralSettingsView.body`
/// stays inside the type-check budget.
///
/// The toggle writes the setting synchronously and then asks the controller
/// to request access, so the switch flips at once and the macOS prompt follows
/// while the user is still looking at what caused it.
struct CalendarSettingsSection: View {
    @Bindable var settings: AppSettings
    var calendar: CalendarController

    var body: some View {
        Section("Calendar") {
            Toggle(
                "Use calendar events for meeting titles and participants",
                isOn: Binding(
                    get: { settings.calendarIntegrationEnabled },
                    set: { newValue in
                        settings.calendarIntegrationEnabled = newValue
                        if newValue { Task { await calendar.activate() } }
                    },
                ),
            )
            .accessibilityIdentifier(A11yID.calendarIntegrationToggle)
            Text(
                """
                A recording made while a calendar event is running (from 10 minutes before its start \
                to 5 minutes after its end) is named after the event, and the invited people are \
                offered as speaker names. Events with a meeting link win over overlapping ones.
                """,
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if settings.calendarIntegrationEnabled {
                accessStatus
                calendarList
            }
        }
        .accessibilityIdentifier(A11yID.calendarSection)
    }

    @ViewBuilder private var accessStatus: some View {
        switch calendar.authorization {
        case .fullAccess:
            EmptyView()

        case .notDetermined:
            Text("Calendar access has not been granted yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .denied, .writeOnly:
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar access is \(calendar.authorization == .writeOnly ? "write-only" : "denied").")
                        .font(.callout.weight(.semibold))
                    Text("Recordings fall back to the window title until Full Access is granted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Calendar Privacy Settings") {
                        NSWorkspace.shared.open(Self.calendarPrivacyURL)
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

    /// Checklist of the account's calendars. Rows are addressed by index in
    /// their identifiers, never by title: `GET /ui/tree` publishes identifiers
    /// unredacted, and a calendar title can name an employer or a client.
    @ViewBuilder private var calendarList: some View {
        if calendar.authorization == .fullAccess, !calendar.availableCalendars.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendars to consider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(calendar.availableCalendars.enumerated()), id: \.element.id) { index, info in
                    Toggle(
                        isOn: Binding(
                            get: { calendar.isCalendarSelected(info.id) },
                            set: { calendar.setCalendar(info.id, selected: $0) },
                        ),
                    ) {
                        HStack(spacing: 4) {
                            Text(info.title)
                            if let account = info.accountTitle {
                                Text("(\(account))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    .accessibilityIdentifier(A11yID.calendarToggle(index))
                }
                Text("All calendars are considered until one is unchecked.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private static let calendarPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
    )!
}
