import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "SpeakerNamingSession")

/// Learning a voice by elimination when the naming dialog is off: the one
/// path besides a dialog confirm on which a pipeline job writes to
/// `speakers.json`. See `ParticipantElimination` for when it applies.
extension SpeakerNamingSession {
    /// Name the leftover participant's speaker(s) and store the one voice the
    /// elimination rests on. Returns `autoNames` with the elimination applied,
    /// unchanged when it does not apply.
    ///
    /// The microphone track is held back on an echo-affected recording here
    /// too (`EchoEmbeddingQuarantine`), although the elimination only ever
    /// picks a far-end speaker on a dual-source job; the unprefixed fallback of
    /// a job whose other track failed is held entirely, as on the confirm path.
    func applyElimination(
        to autoNames: [String: String],
        matched: [String: String],
        diarization: DiarizationResult,
        job: (id: UUID, participants: [String], isDualSource: Bool),
        matcher: SpeakerMatcher,
    ) -> [String: String] {
        guard let elimination = ParticipantElimination.resolve(
            mapping: matched,
            speakingTimes: diarization.speakingTimes,
            participants: job.participants,
            isDualSource: job.isDualSource,
        ) else { return autoNames }

        let label = elimination.learnLabel
        if let delegate, let name = elimination.names[label], let embedding = diarization.embeddings?[label] {
            let admissible = EchoEmbeddingQuarantine.admissible(
                [label: embedding],
                verdict: EchoVerdict(delegate.job(withID: job.id)?.echo),
                isDualSource: job.isDualSource,
            )
            if admissible.isEmpty {
                logger.info("[recognition] elimination named a speaker; voice held by echo quarantine")
            } else {
                delegate.updateSpeakerDB(
                    matcher: matcher,
                    mapping: [label: name],
                    embeddings: admissible,
                    speakingTimes: diarization.speakingTimes,
                )
                logger.info("[recognition] learned 1 voice by elimination")
            }
        }
        return autoNames.merging(elimination.names) { _, eliminated in eliminated }
    }
}
