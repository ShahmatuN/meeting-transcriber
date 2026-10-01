import Foundation

/// `12:05`, or `1:02:05` past the hour. Negative spans read as zero, which is
/// what a clock adjusted backwards mid-recording should show.
enum ElapsedTime {
    static func string(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
}
