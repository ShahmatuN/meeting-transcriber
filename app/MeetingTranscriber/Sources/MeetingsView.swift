import Combine
import SwiftUI

/// Where the Meetings window's navigation stack can go.
enum MeetingsRoute: Hashable {
    case record(MeetingRecord)
    case live
}

/// The Meetings window: today's calendar, the recording in progress, and every
/// meeting in the protocols folder grouped by day. A row opens the meeting's
/// transcript and protocol. No search on purpose; the list is the index.
///
/// Receives its data and actions as plain values and closures, like
/// `SettingsView`, so the scene in `MeetingTranscriberApp` stays the only
/// place that knows about `AppState`.
struct MeetingsView: View {
    let store: MeetingLibraryStore
    let liveRecording: LiveRecordingSummary?
    let processing: [ProcessingMeeting]
    let liveCaptions: LiveCaptionsState
    let calendarEnabled: Bool
    let outputDir: URL
    let onReload: () -> Void
    let onStopRecording: () -> Void
    let onOpenURL: (URL) -> Void
    let onRevealInFinder: (URL) -> Void
    let onOpenSettings: () -> Void

    @State private var path: [MeetingsRoute] = []

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: MeetingsRoute.self, destination: destination)
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear(perform: onReload)
        .onReceive(refreshTimer) { _ in onReload() }
        .onChange(of: processing) { onReload() }
        .onChange(of: liveRecording == nil) { _, ended in
            // A finished recording leaves nothing to show on the live page.
            if ended, path.last == .live { path.removeLast() }
            onReload()
        }
    }

    // MARK: - Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ComingUpSection(
                    upcoming: store.upcoming,
                    calendarEnabled: calendarEnabled,
                    onJoin: onOpenURL,
                    onOpenSettings: onOpenSettings,
                )
                if let liveRecording {
                    LiveRecordingCard(
                        recording: liveRecording,
                        onOpen: { path.append(.live) },
                        onStop: onStopRecording,
                    )
                }
                processingSection
                PastMeetingsSection(
                    records: store.records,
                    processingBasenames: processingBasenames,
                ) { path.append(.record($0)) }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(MeetingsStyle.windowBackground)
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem {
                Button(action: onReload) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    /// Jobs whose transcript is not on disk yet. A job that already wrote its
    /// draft shows up in the day list instead, with a processing badge.
    @ViewBuilder private var processingSection: some View {
        let recordStems = Set(store.records.map(\.basename))
        let pending = processing.filter { job in
            job.basename.map { !recordStems.contains($0) } ?? true
        }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MeetingsSectionHeader(title: "Processing")
                ForEach(pending) { job in
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(job.title).lineLimit(1)
                        Spacer()
                        Text(job.stateLabel).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var processingBasenames: [String: String] {
        var labels: [String: String] = [:]
        for job in processing {
            if let basename = job.basename { labels[basename] = job.stateLabel }
        }
        return labels
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: MeetingsRoute) -> some View {
        switch route {
        case let .record(record):
            MeetingDetailView(
                record: currentVersion(of: record),
                processingLabel: processingBasenames[record.basename],
                readText: { MeetingLibraryStore.readText($0, scope: outputDir) },
                onOpenURL: onOpenURL,
                onRevealInFinder: onRevealInFinder,
            )

        case .live:
            if let liveRecording {
                LiveRecordingDetailView(
                    recording: liveRecording,
                    liveCaptions: liveCaptions,
                    onStop: onStopRecording,
                )
            } else {
                ContentUnavailableView("Recording finished", systemImage: "checkmark.circle")
            }
        }
    }

    /// The route holds the record as it was when tapped; a reload since then
    /// (the draft replaced by the final transcript, a protocol written) is
    /// picked up by looking it up again.
    private func currentVersion(of record: MeetingRecord) -> MeetingRecord {
        store.records.first { $0.basename == record.basename } ?? record
    }
}

// MARK: - Style

enum MeetingsStyle {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBorder = Color.primary.opacity(0.08)
    static let eventBar = Color.teal.opacity(0.7)
    static let titleFont = Font.system(.title, design: .serif)

    /// A stable pastel per title, for the letter tile in front of each row.
    static func tileColor(for title: String) -> Color {
        let palette: [Color] = [.yellow, .purple, .orange, .pink, .mint, .blue, .green]
        let sum = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(sum) % palette.count].opacity(0.25)
    }
}

struct MeetingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

private struct MeetingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MeetingsStyle.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MeetingsStyle.cardBorder))
    }
}

// MARK: - Coming up

private struct ComingUpSection: View {
    let upcoming: [UpcomingMeeting]
    let calendarEnabled: Bool
    let onJoin: (URL) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coming up").font(MeetingsStyle.titleFont)
            MeetingsCard {
                HStack(alignment: .top, spacing: 28) {
                    dayColumn
                    eventColumn
                }
            }
        }
    }

    private var dayColumn: some View {
        let now = Date()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(now, format: .dateTime.day())
                .font(.system(size: 30, design: .serif))
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.month(.wide)).font(.callout)
                Text(now, format: .dateTime.weekday(.abbreviated))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 130, alignment: .leading)
    }

    @ViewBuilder private var eventColumn: some View {
        if !calendarEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your calendar to see today's meetings here.")
                    .foregroundStyle(.secondary)
                Button("Open Settings…", action: onOpenSettings)
            }
        } else if upcoming.isEmpty {
            Text("No more meetings today.")
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(upcoming) { meeting in
                    UpcomingEventRow(meeting: meeting, onJoin: onJoin)
                }
            }
        }
    }
}

private struct UpcomingEventRow: View {
    let meeting: UpcomingMeeting
    let onJoin: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(MeetingsStyle.eventBar)
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.event.title.isEmpty ? "Untitled event" : meeting.event.title)
                    .lineLimit(1)
                timeLine
            }
            Spacer(minLength: 8)
            if let url = meeting.conferenceURL {
                joinButton(url)
            }
        }
    }

    private var timeLine: some View {
        HStack(spacing: 4) {
            if meeting.isNow {
                Text("Now ·").foregroundStyle(.green)
            }
            Text(meeting.event.start, format: .dateTime.hour().minute())
            Text("–")
            Text(meeting.event.end, format: .dateTime.hour().minute())
        }
        .font(.caption)
        .foregroundStyle(meeting.isNow ? Color.green : Color.secondary)
    }

    @ViewBuilder
    private func joinButton(_ url: URL) -> some View {
        if meeting.isNow {
            Button("Join") { onJoin(url) }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .controlSize(.small)
        } else {
            Button("Join") { onJoin(url) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Recording now

struct LiveRecordingCard: View {
    let recording: LiveRecordingSummary
    let onOpen: () -> Void
    let onStop: () -> Void

    var body: some View {
        MeetingsCard {
            HStack(spacing: 14) {
                RecordingDot()
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Recording")
                        if let start = recording.startedAt {
                            Text("·")
                            ElapsedText(since: start)
                        }
                        Text("·")
                        Text(recording.appName).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if recording.isManual {
                    Button("Stop", role: .destructive, action: onStop)
                        .controlSize(.small)
                        .accessibilityIdentifier(A11yID.meetingsStopRecording)
                }
                Button("Open", action: onOpen)
                    .controlSize(.small)
                    .accessibilityIdentifier(A11yID.meetingsOpenLiveRecording)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

struct RecordingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityLabel("Recording")
    }
}

struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(ElapsedTime.string(seconds: context.date.timeIntervalSince(since)))
                .monospacedDigit()
        }
    }
}

// MARK: - Past meetings

private struct PastMeetingsSection: View {
    let records: [MeetingRecord]
    /// File stem → pipeline state label, for rows whose transcript is a draft.
    let processingBasenames: [String: String]
    let onOpen: (MeetingRecord) -> Void

    var body: some View {
        if records.isEmpty {
            Text("Finished meetings appear here once their transcript is saved.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(MeetingLibrary.groupedByDay(records), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        MeetingsSectionHeader(title: Self.dayLabel(group.day))
                            .padding(.bottom, 6)
                        ForEach(group.records) { record in
                            MeetingRow(
                                record: record,
                                processingLabel: processingBasenames[record.basename],
                            ) { onOpen(record) }
                        }
                    }
                }
            }
        }
    }

    static func dayLabel(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return sameYear
            ? day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}

private struct MeetingRow: View {
    let record: MeetingRecord
    let processingLabel: String?
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let processingLabel {
                    Text(processingLabel)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                Text(record.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.05) : .clear),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var tile: some View {
        Text(String(record.title.first ?? "M").uppercased())
            .font(.system(.body, design: .serif))
            .frame(width: 30, height: 30)
            .background(MeetingsStyle.tileColor(for: record.title), in: RoundedRectangle(cornerRadius: 6))
    }

    private var subtitle: String {
        switch (record.protocolURL != nil, record.transcriptURL != nil) {
        case (true, true): "Summary · Transcript"
        case (true, false): "Summary"
        case (false, true): "Transcript"
        case (false, false): ""
        }
    }
}
