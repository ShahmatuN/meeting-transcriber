import Foundation

/// The running recording, as the Meetings window shows it.
struct LiveRecordingSummary: Equatable {
    let title: String
    let appName: String
    let startedAt: Date?
    /// Whether the user can stop it from the window: true for a manual or
    /// microphone recording. An auto-detected meeting ends on its own when the
    /// call does, and stopping the watch loop to end it would also stop
    /// watching for the next one.
    let isManual: Bool
}

/// A queued or running pipeline job, reduced to what the Meetings window
/// lists while the transcript is not final yet.
struct ProcessingMeeting: Identifiable, Equatable {
    let id: UUID
    let title: String
    let stateLabel: String
    /// The output file stem once the transcribe stage fixed it, so the row of
    /// a draft transcript already on disk can say it is still being worked on.
    let basename: String?
}

/// What the Meetings window lists: the meetings in the protocols folder and
/// what is left on today's calendar. Reloaded by the window (on open, once a
/// minute, and when a job finishes), never polled in the background, so a
/// closed window costs nothing.
@Observable
@MainActor
final class MeetingLibraryStore {
    private(set) var records: [MeetingRecord] = []
    private(set) var upcoming: [UpcomingMeeting] = []

    func reload(
        outputDir: URL,
        terminalRecords: [JobStatusDTO],
        calendar: CalendarController,
        now: Date = Date(),
    ) {
        let accessing = outputDir.startAccessingSecurityScopedResource()
        defer { if accessing { outputDir.stopAccessingSecurityScopedResource() } }
        let scanned = MeetingLibrary.scan(
            protocolsDir: outputDir.appendingPathComponent("protocols"),
            knownTitles: MeetingLibrary.knownTitles(from: terminalRecords),
        )
        if scanned != records { records = scanned }
        let next = calendar.upcomingMeetings(now: now)
        if next != upcoming { upcoming = next }
    }

    /// Read one of the listed files. `outputDir` is the scope to open first:
    /// in the sandboxed build a user-picked folder is reachable only through
    /// its bookmark-resolved URL.
    nonisolated static func readText(_ url: URL, scope outputDir: URL) -> String? {
        let accessing = outputDir.startAccessingSecurityScopedResource()
        defer { if accessing { outputDir.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
