import SwiftUI

/// One finished meeting: its protocol (the generated summary) and its
/// transcript, read from the files the pipeline wrote.
struct MeetingDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case transcript = "Transcript"

        var id: String {
            rawValue
        }
    }

    let record: MeetingRecord
    /// The pipeline state while the transcript on disk is still a draft.
    let processingLabel: String?
    let readText: (URL) -> String?
    let onOpenURL: (URL) -> Void
    let onRevealInFinder: (URL) -> Void

    @State private var tab: Tab = .transcript
    @State private var transcript: TranscriptDocument?
    /// The protocol's blocks; nil until loaded or when unreadable.
    @State private var protocolDocument: ProtocolDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if availableTabs.count > 1 {
                    Picker("View", selection: $tab) {
                        ForEach(availableTabs) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier(A11yID.meetingDetailTabPicker)
                }
                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(MeetingsStyle.windowBackground)
        .navigationTitle(record.title)
        .toolbar { toolbarContent }
        // Keyed on the modification date so a draft transcript replaced by
        // the final one, or a protocol written later, is re-read.
        .task(id: record.modifiedAt) { load() }
    }

    private var availableTabs: [Tab] {
        var tabs: [Tab] = []
        if record.protocolURL != nil { tabs.append(.summary) }
        if record.transcriptURL != nil { tabs.append(.transcript) }
        return tabs
    }

    private var effectiveTab: Tab {
        availableTabs.contains(tab) ? tab : (availableTabs.first ?? .transcript)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.title)
                .font(MeetingsStyle.titleFont)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(record.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                if let processingLabel {
                    Text("·")
                    ProgressView().controlSize(.mini)
                    Text(processingLabel)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch effectiveTab {
        case .summary:
            if let protocolDocument {
                MarkdownBlocksView(blocks: protocolDocument.blocks)
            } else {
                unreadable
            }

        case .transcript:
            if let transcript, !transcript.isEmpty {
                TranscriptView(document: transcript)
            } else if transcript != nil {
                Text("The transcript is empty.").foregroundStyle(.secondary)
            } else {
                unreadable
            }
        }
    }

    private var unreadable: some View {
        Text("This file could not be read. It may have been moved or deleted.")
            .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if let file = currentFile {
                Button { onRevealInFinder(file) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show in Finder")
                Button { onOpenURL(file) } label: {
                    Label("Open in Default App", systemImage: "arrow.up.forward.app")
                }
                .help("Open in default app")
            }
        }
    }

    private var currentFile: URL? {
        switch effectiveTab {
        case .summary: record.protocolURL
        case .transcript: record.transcriptURL ?? record.protocolURL
        }
    }

    private func load() {
        transcript = record.transcriptURL.flatMap(readText).map(TranscriptDocument.parse)
        protocolDocument = record.protocolURL.flatMap(readText).map { ProtocolDocument(blocks: MarkdownBlock.parse($0)) }
        if record.protocolURL != nil, tab == .transcript, transcript == nil {
            tab = .summary
        }
    }
}

/// A loaded protocol. A wrapper so "not loaded" and "loaded, empty" stay
/// distinct without an optional collection.
private struct ProtocolDocument {
    let blocks: [MarkdownBlock]
}

// MARK: - Transcript

struct TranscriptView: View {
    let document: TranscriptDocument

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(document.turns) { turn in
                VStack(alignment: .leading, spacing: 4) {
                    if turn.speaker != nil || turn.timestamp != nil {
                        HStack(spacing: 8) {
                            if let speaker = turn.speaker {
                                Text(speaker).font(.callout.weight(.semibold))
                            }
                            if let timestamp = turn.timestamp {
                                Text(timestamp)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(turn.text)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - Markdown

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownBlock.inline(text))
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 10 : 4)

        case let .bullet(indent, text):
            listItem(marker: "•", indent: indent, text: text)

        case let .numbered(indent, marker, text):
            listItem(marker: marker, indent: indent, text: text)

        case let .quote(text):
            Text(MarkdownBlock.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 2)
                }

        case let .paragraph(text):
            Text(MarkdownBlock.inline(text))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func listItem(marker: String, indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(.secondary)
            Text(MarkdownBlock.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indent) * 18)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(.title2, design: .serif)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

// MARK: - Live recording

/// The recording in progress. Shows the live captions when that feature is
/// on; the transcript itself is written once the recording ends and the
/// pipeline has run.
struct LiveRecordingDetailView: View {
    let recording: LiveRecordingSummary
    let liveCaptions: LiveCaptionsState
    let onStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recording.title).font(MeetingsStyle.titleFont)
                    HStack(spacing: 8) {
                        RecordingDot()
                        Text("Recording")
                        if let start = recording.startedAt {
                            ElapsedText(since: start)
                        }
                        Text("·")
                        Text(recording.appName)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                if recording.isManual {
                    Button("Stop Recording", role: .destructive, action: onStop)
                }
                Divider()
                captions
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(MeetingsStyle.windowBackground)
        .navigationTitle(recording.title)
    }

    @ViewBuilder private var captions: some View {
        if let backend = liveCaptions.activeBackend {
            VStack(alignment: .leading, spacing: 12) {
                MeetingsSectionHeader(title: "Live captions · \(backend)")
                ForEach(Array(liveCaptions.recentFinals.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.speaker).font(.callout.weight(.semibold))
                        Text(line.text)
                    }
                }
                hypothesis(liveCaptions.hypothesisMic, speaker: liveCaptions.micLabel)
                hypothesis(liveCaptions.hypothesisApp, speaker: liveCaptions.appLabel)
            }
            .textSelection(.enabled)
        } else {
            Text(
                "The transcript appears in the meeting list once the recording ends and has been processed. "
                    + "Turn on live transcription in Settings → Transcribe to follow along here.",
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func hypothesis(_ text: String, speaker: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker).font(.callout.weight(.semibold))
                Text(text).foregroundStyle(.secondary).italic()
            }
        }
    }
}
