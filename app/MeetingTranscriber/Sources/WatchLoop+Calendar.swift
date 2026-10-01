import Foundation

/// How a scheduled calendar event changes what `handleMeeting` records about
/// a meeting. Pure helpers, split out so `WatchLoop.swift` stays under the
/// line cap and so the merge rule can be pinned without a loop.
extension WatchLoop {
    /// The participant list a job carries: the names read off the meeting
    /// app's own roster first (Teams, via Accessibility), then the calendar
    /// attendees that roster did not already name. The roster leads because it
    /// says who actually showed up; the invitation adds the people whose names
    /// the roster could not read, and never duplicates one it did.
    static func mergeParticipants(roster: [String], scheduled: [String]) -> [String] {
        var seen = Set(roster.map { $0.lowercased() })
        var result = roster
        for name in scheduled where seen.insert(name.lowercased()).inserted {
            result.append(name)
        }
        return result
    }
}
