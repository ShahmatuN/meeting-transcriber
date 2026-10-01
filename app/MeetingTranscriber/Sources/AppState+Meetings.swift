import Foundation

/// What the Meetings window reads from the app: the running recording, the
/// jobs still on their way to a transcript, and the reload of the list.
extension AppState {
    /// The running recording, or nil when nothing is recording.
    var liveRecording: LiveRecordingSummary? {
        guard let loop = watching.watchLoop, loop.state == .recording else { return nil }
        let manual = loop.manualRecordingInfo
        return LiveRecordingSummary(
            title: loop.recordingTitle ?? manual?.title ?? "Recording",
            appName: manual?.appName ?? loop.currentMeeting?.pattern.appName ?? "",
            startedAt: loop.recordingStartedAt,
            isManual: manual != nil,
        )
    }

    /// Jobs still on their way to a final transcript.
    var processingMeetings: [ProcessingMeeting] {
        pipeline.queue.jobs.filter { !$0.state.isTerminal }.map { job in
            ProcessingMeeting(
                id: job.id, title: job.meetingTitle, stateLabel: job.state.label, basename: job.namingSlug,
            )
        }
    }

    func reloadMeetingLibrary() {
        meetingLibrary.reload(
            outputDir: settings.effectiveOutputDir,
            terminalRecords: pipeline.terminalJobStore.records,
            calendar: calendar,
        )
    }
}
