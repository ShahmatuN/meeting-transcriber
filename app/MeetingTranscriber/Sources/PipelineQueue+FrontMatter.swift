import Foundation

extension PipelineQueue {
    /// The YAML header for a job's transcript, or nil when its layout has
    /// none. Built from the job (title, start, app, participants, calendar
    /// event, diarizer mode), the queue's engine, and the segments exactly as
    /// rendered, so the speaking times describe the text below them.
    func frontMatter(forJobID jobID: UUID, segments: [TimestampedSegment]) -> String? {
        guard transcriptOutputOptions(forJobID: jobID).layout.hasFrontMatter,
              let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        let live = segments.filter { !$0.suppressed }
        let facts = TranscriptFrontMatter.Facts(
            title: job.meetingTitle,
            start: job.meetingStartTime,
            durationSeconds: live.map(\.end).max(),
            appName: job.appName,
            participants: job.participants,
            calendarEventID: job.calendarEventID,
            engine: engine.map { Self.engineName(of: $0) },
            diarizer: job.usedDiarizerMode?.rawValue,
            speakers: TranscriptFrontMatter.speakers(from: live),
        )
        return TranscriptFrontMatter.render(facts)
    }

    /// `WhisperKitEngine` → `WhisperKit`: the type name without the suffix
    /// every engine carries.
    static func engineName(of engine: any TranscribingEngine) -> String {
        let name = String(describing: type(of: engine))
        return name.hasSuffix("Engine") ? String(name.dropLast("Engine".count)) : name
    }
}
