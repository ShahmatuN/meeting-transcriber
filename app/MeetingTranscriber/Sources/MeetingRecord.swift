import Foundation

/// One finished (or still-processing) meeting as the Meetings window lists it:
/// the transcript and protocol files the pipeline wrote under one basename in
/// `<outputDir>/protocols/`.
///
/// Built from the folder rather than from the pipeline's job list on purpose.
/// The queue reaps finished jobs after a minute and `TerminalJobStore` keeps a
/// bounded window of them, while the files are what the user actually keeps;
/// listing the folder shows every meeting the app ever wrote there, imports
/// included, and survives a reinstall.
struct MeetingRecord: Identifiable, Hashable {
    /// The shared file stem, `{yyyyMMdd_HHmm}_{slug}[_{shortID}]`.
    let basename: String
    let title: String
    /// The meeting start encoded in the stem, or the newest file's modification
    /// date for a stem that carries no stamp (a file renamed by hand).
    let date: Date
    let transcriptURL: URL?
    let protocolURL: URL?
    /// The newest modification date across both files, so a detail view keyed
    /// on it reloads when the draft transcript is replaced by the final one.
    let modifiedAt: Date

    var id: String {
        basename
    }
}

extension MeetingRecord {
    struct ParsedBasename: Equatable {
        let date: Date
        /// The title-ish part of the stem, without stamp or collision suffix.
        let slug: String
    }

    private static let stampFormatter = DateFormatter.filenameStamp("yyyyMMdd_HHmm")

    /// Split a stem into its meeting-start stamp and its slug, dropping the
    /// trailing eight-hex `shortID` collision guard
    /// (`ProtocolGenerator.basename`). Nil when the stem does not start with a
    /// stamp.
    static func parse(basename: String) -> ParsedBasename? {
        guard let match = basename.firstMatch(of: /^(\d{8}_\d{4})(?:_(.*))?$/),
              let date = stampFormatter.date(from: String(match.1))
        else { return nil }
        var slug = match.2.map(String.init) ?? ""
        if let suffix = slug.firstMatch(of: /(?:^|_)[0-9a-f]{8}$/) {
            slug.removeSubrange(suffix.range)
        }
        return ParsedBasename(date: date, slug: slug)
    }

    /// A readable title from a slug: underscores back to spaces, first letter
    /// upper-cased. Lossy (the slug lower-cased the original and dropped its
    /// punctuation), so only the fallback when no stored title is known.
    static func humanize(slug: String) -> String {
        let words = slug.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let first = words.first else { return "Meeting" }
        return first.uppercased() + words.dropFirst()
    }
}

/// Reads the protocols folder into `MeetingRecord`s.
enum MeetingLibrary {
    static let transcriptExtension = "txt"
    static let protocolExtension = "md"

    /// Every meeting in `protocolsDir`, newest first.
    ///
    /// - Parameter knownTitles: stored meeting titles keyed by file stem, from
    ///   `TerminalJobStore`. Preferred over the slug, which lost the original
    ///   casing and punctuation.
    static func scan(
        protocolsDir: URL,
        knownTitles: [String: String] = [:],
        fileManager: FileManager = .default,
    ) -> [MeetingRecord] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: protocolsDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles],
        ) else { return [] }

        var transcripts: [String: URL] = [:]
        var protocols: [String: URL] = [:]
        var modified: [String: Date] = [:]
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == transcriptExtension || ext == protocolExtension else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            if ext == transcriptExtension { transcripts[stem] = url } else { protocols[stem] = url }
            let date = values?.contentModificationDate ?? .distantPast
            modified[stem] = max(modified[stem] ?? .distantPast, date)
        }

        let stems = Set(transcripts.keys).union(protocols.keys)
        return stems.map { stem in
            let parsed = MeetingRecord.parse(basename: stem)
            let modifiedAt = modified[stem] ?? .distantPast
            let title = knownTitles[stem]
                ?? parsed.map { MeetingRecord.humanize(slug: $0.slug) }
                ?? stem
            return MeetingRecord(
                basename: stem,
                title: title,
                date: parsed?.date ?? modifiedAt,
                transcriptURL: transcripts[stem],
                protocolURL: protocols[stem],
                modifiedAt: modifiedAt,
            )
        }
        .sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.basename > rhs.basename : lhs.date > rhs.date
        }
    }

    /// Stored titles keyed by file stem, from the finished-job records. A
    /// record names its files by full path; only the stem is compared, so a
    /// moved output folder still matches.
    static func knownTitles(from records: [JobStatusDTO]) -> [String: String] {
        var titles: [String: String] = [:]
        for record in records {
            for path in [record.transcriptPath, record.protocolPath].compactMap(\.self) {
                let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                titles[stem] = record.meetingTitle
            }
        }
        return titles
    }

    /// Records grouped by calendar day, newest day first, each group keeping
    /// the input order.
    static func groupedByDay(
        _ records: [MeetingRecord], calendar: Calendar = .current,
    ) -> [(day: Date, records: [MeetingRecord])] {
        var order: [Date] = []
        var groups: [Date: [MeetingRecord]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.date)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(record)
        }
        return order.sorted(by: >).map { (day: $0, records: groups[$0] ?? []) }
    }
}
