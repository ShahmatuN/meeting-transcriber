import Foundation

/// How a finished transcript is laid out on disk (`AppSettings.transcriptLayout`,
/// captured per job at enqueue like the other output options).
///
/// `compact` is the shape the app has always written: one `[MM:SS] Speaker:`
/// line per block, a block ending at any pause over two seconds, nothing
/// else in the file. `readable` is for a transcript that is read rather than
/// grepped, and for one handed to an LLM or a wiki: a speaker's turn stays one
/// paragraph until the other side speaks or a long pause suggests a new
/// topic, paragraphs are separated by a blank line, and the file opens with a
/// YAML header carrying what the file name cannot (date, start, duration,
/// participants, who spoke how long). The line shape is the same in both, so
/// the Meetings window parser and the late speaker-rename keep working.
enum TranscriptLayout: String, Codable, CaseIterable {
    case compact
    case readable

    var label: String {
        switch self {
        case .compact: "Compact (one line per utterance)"
        case .readable: "Readable (paragraphs + metadata header)"
        }
    }

    /// Longest pause that still continues a same-speaker paragraph.
    var mergeGap: TimeInterval {
        switch self {
        case .compact: DiarizationProcess.mergeGapThreshold
        case .readable: 15
        }
    }

    /// What goes between two rendered blocks.
    var blockSeparator: String {
        switch self {
        case .compact: "\n"
        case .readable: "\n\n"
        }
    }

    var hasFrontMatter: Bool {
        self == .readable
    }
}
