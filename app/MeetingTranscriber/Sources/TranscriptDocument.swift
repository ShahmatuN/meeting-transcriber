import Foundation

/// A saved transcript, split into speaker turns for the Meetings window.
///
/// The pipeline writes one segment per line as `[mm:ss] Speaker: text`
/// (`[h:mm:ss]` past the hour). Consecutive lines by the same speaker are
/// folded into one turn so the reader sees paragraphs rather than a log. A
/// line that does not have that shape (a transcript note, a hand edit) is kept
/// as a turn without speaker or timestamp, never dropped. The YAML header a
/// `.readable` transcript opens with is metadata, not speech, and is left out.
struct TranscriptDocument: Equatable {
    struct Turn: Equatable, Identifiable {
        let id: Int
        /// The first segment's timestamp as written, e.g. `"01:23"`.
        let timestamp: String?
        let speaker: String?
        var text: String
    }

    let turns: [Turn]

    var isEmpty: Bool {
        turns.isEmpty
    }

    static func parse(_ text: String) -> Self {
        var turns: [Turn] = []
        for rawLine in TranscriptFrontMatter.strip(text).split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let match = line.firstMatch(of: /^\[(\d{1,2}(?::\d{2}){1,2})\]\s*([^:]{1,80}):\s?(.*)$/) {
                let speaker = String(match.2).trimmingCharacters(in: .whitespaces)
                let body = String(match.3)
                if let last = turns.last, last.speaker == speaker {
                    turns[turns.count - 1].text += " " + body
                } else {
                    turns.append(Turn(id: turns.count, timestamp: String(match.1), speaker: speaker, text: body))
                }
            } else {
                turns.append(Turn(id: turns.count, timestamp: nil, speaker: nil, text: line))
            }
        }
        return Self(turns: turns)
    }
}
