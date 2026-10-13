import Foundation

/// Names a speaker by elimination when the naming dialog is off: once voice
/// matches and the pinned microphone name have claimed theirs, a single
/// invited participant left over must be whoever is still unnamed. The one
/// speaker that decision rests on is also the one whose voice is learned, so
/// the next meeting with that person is recognised by voice.
///
/// `SpeakerMatcher.preMatchParticipants` already pairs leftovers with
/// participants for the dialog, but only when the counts match exactly, which
/// a real 1-1 almost never satisfies: the remote track routinely comes back as
/// one long cluster plus a few seconds of diarization noise, or as two long
/// clusters of the same voice split mid-call. This type ignores the noise and
/// handles the split, and it says which single speaker is safe to learn from.
enum ParticipantElimination {
    /// Clusters shorter than this are diarization noise: neither named nor
    /// counted against a match. Also comfortably above the matcher's 3 s
    /// centroid-quality floor, so a learned voice always seeds the centroid.
    static let minSpeakingTime: TimeInterval = 30

    struct Resolution: Equatable {
        /// Labels to name after the leftover participant.
        let names: [String: String]
        /// The one label whose embedding may be stored under that name.
        let learnLabel: String
    }

    /// - Parameters:
    ///   - mapping: label → name after voice matching and pins, before any
    ///     participant pre-match; an unnamed label maps to itself.
    ///   - participants: invited participants other than the user.
    static func resolve(
        mapping: [String: String],
        speakingTimes: [String: TimeInterval],
        participants: [String],
        isDualSource: Bool,
    ) -> Resolution? {
        let used = Set(mapping.values)
        let leftover = participants.filter { !used.contains($0) }
        guard leftover.count == 1, let name = leftover.first else { return nil }

        let unnamed = mapping.keys
            .filter { mapping[$0] == $0 && (speakingTimes[$0] ?? 0) >= minSpeakingTime }
            .sorted { (speakingTimes[$0] ?? 0) > (speakingTimes[$1] ?? 0) }
        guard let dominant = unnamed.first else { return nil }

        if !isDualSource {
            // The user's own voice is in the same mix; only one speaker left
            // unnamed means it was recognised and the rest is the participant.
            return unnamed.count == 1 ? Resolution(names: [dominant: name], learnLabel: dominant) : nil
        }

        // An unnamed voice in the room could be the participant as much as
        // anyone on the far end, so there is nothing to eliminate.
        let tracks = Set(unnamed.map { SpeakerKey(encoded: $0).track })
        guard tracks == [.app] else { return nil }
        if unnamed.count == 1 {
            return Resolution(names: [dominant: name], learnLabel: dominant)
        }
        // Several long far-end clusters: in a 1-1 that nobody on the far end
        // was recognised in, they are one person split by the diarizer. Name
        // them all, but learn only the longest: averaging two clusters into
        // one centroid would blur it if the split was real after all.
        let farEndRecognised = mapping.contains { label, assigned in
            assigned != label && SpeakerKey(encoded: label).track == .app
        }
        guard participants.count == 1, !farEndRecognised else { return nil }
        return Resolution(
            names: Dictionary(uniqueKeysWithValues: unnamed.map { ($0, name) }),
            learnLabel: dominant,
        )
    }
}
