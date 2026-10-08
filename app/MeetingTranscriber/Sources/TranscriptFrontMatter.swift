import Foundation

/// The YAML header a `.readable` transcript opens with, and the three things
/// everything downstream needs to do with it: strip it before the text goes
/// to a language model or a parser, rename the speakers in it when the user
/// names them late, and know whether a given text already carries one.
///
/// Every string value is double-quoted, times included, because `16:00` is a
/// sexagesimal integer to a YAML 1.1 reader and a title can carry a colon.
/// Keys are quoted too, so the late rename can anchor on `  "label": ` the
/// way the body rename anchors on `] label:`.
enum TranscriptFrontMatter {
    static let fence = "---"

    struct Facts {
        var title: String
        var start: Date?
        var durationSeconds: TimeInterval?
        var appName: String
        var participants: [String]
        var calendarEventID: String?
        var engine: String?
        var diarizer: String?
        /// Who spoke for how long, in the names the transcript body uses.
        var speakers: [(name: String, seconds: TimeInterval)]
    }

    static func render(_ facts: Facts, timeZone: TimeZone = .current) -> String {
        var lines = [fence, "title: \(quoted(facts.title))"]
        if let start = facts.start {
            lines.append("date: \(format(start, "yyyy-MM-dd", timeZone))")
            lines.append("start: \(quoted(format(start, "HH:mm", timeZone)))")
            if let duration = facts.durationSeconds {
                lines.append("end: \(quoted(format(start.addingTimeInterval(duration), "HH:mm", timeZone)))")
            }
        }
        if let duration = facts.durationSeconds {
            lines.append("duration: \(quoted(clock(duration)))")
        }
        lines.append("app: \(quoted(facts.appName))")
        if !facts.participants.isEmpty {
            lines.append("participants: [\(facts.participants.map(quoted).joined(separator: ", "))]")
        }
        if let id = facts.calendarEventID {
            lines.append("calendar_event: \(quoted(id))")
        }
        if let engine = facts.engine {
            lines.append("engine: \(quoted(engine))")
        }
        if let diarizer = facts.diarizer {
            lines.append("diarizer: \(quoted(diarizer))")
        }
        if !facts.speakers.isEmpty {
            lines.append("speakers:")
            let ordered = facts.speakers.sorted { a, b in
                a.seconds != b.seconds ? a.seconds > b.seconds : a.name < b.name
            }
            for speaker in ordered {
                lines.append("  \(quoted(speaker.name)): \(quoted(clock(speaker.seconds)))")
            }
        }
        lines.append(fence)
        return lines.joined(separator: "\n")
    }

    /// Speaking time per labelled speaker, from the segments as rendered.
    static func speakers(from segments: [TimestampedSegment]) -> [(name: String, seconds: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for seg in segments where !seg.speaker.isEmpty && !seg.suppressed {
            totals[seg.speaker, default: 0] += max(0, seg.end - seg.start)
        }
        return totals.map { (name: $0.key, seconds: $0.value) }
    }

    /// The header above the text, separated by a blank line. `nil` or empty
    /// header leaves the text alone.
    static func prepend(_ header: String?, to text: String) -> String {
        guard let header, !header.isEmpty else { return text }
        guard !text.isEmpty else { return header }
        return header + "\n\n" + text
    }

    static func hasFrontMatter(_ text: String) -> Bool {
        split(text).header != nil
    }

    /// The text without its header, for a parser or a language model.
    static func strip(_ text: String) -> String {
        split(text).body
    }

    /// Rename speakers inside the header's `speakers:` map, in step with the
    /// body rename `reapplySpeakerNames` does on `] label:`. Text without a
    /// header comes back unchanged.
    static func renameSpeakers(in text: String, renames: [(from: String, to: String)]) -> String {
        let (header, body) = split(text)
        guard var header else { return text }
        for rename in renames where rename.from != rename.to {
            header = header.replacingOccurrences(
                of: "\n  \(quoted(rename.from)): ", with: "\n  \(quoted(rename.to)): ",
            )
        }
        return prepend(header, to: body)
    }

    /// The header (fences included) and the body with its leading blank
    /// lines removed, or no header and the text as given.
    static func split(_ text: String) -> (header: String?, body: String) {
        guard text.hasPrefix(fence + "\n") else { return (nil, text) }
        var searchFrom = text.index(text.startIndex, offsetBy: fence.count + 1)
        while let range = text.range(of: "\n" + fence, range: searchFrom ..< text.endIndex) {
            let lineEnd = range.upperBound
            if lineEnd == text.endIndex || text[lineEnd] == "\n" {
                var body = String(text[lineEnd...])
                while body.hasPrefix("\n") {
                    body.removeFirst()
                }
                return (String(text[..<lineEnd]), body)
            }
            searchFrom = lineEnd
        }
        return (nil, text)
    }

    // MARK: - Formatting

    static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// `H:MM:SS`, hours unpadded, so the value is the same shape at any length.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
