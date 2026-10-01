import Foundation

/// View-facing helpers of `WatchLoop`, moved out of `WatchLoop.swift` to keep
/// it under the line cap. Neither touches loop state beyond reading `state`.
extension WatchLoop {
    /// Strip app suffixes from meeting titles for cleaner display.
    static func cleanTitle(_ title: String) -> String {
        let suffixes = [" | Microsoft Teams", " - Zoom", " - Webex"]
        for suffix in suffixes where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return title
    }

    /// Map WatchLoop state to TranscriberState for compatibility with existing UI.
    var transcriberState: TranscriberState {
        switch state {
        case .idle: .idle
        case .watching: .watching
        case .recording: .recording
        case .error: .error
        }
    }
}
