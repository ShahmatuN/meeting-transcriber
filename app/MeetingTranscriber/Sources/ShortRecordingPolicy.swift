import AVFoundation
import Foundation

/// Whether a recording is too short to have been a meeting.
///
/// A detector fires on signals that are not meeting-exclusive (a WebRTC
/// assertion on a lobby page, a voice message holding the microphone), and
/// the end-grace stops such a capture after seconds. Left alone, each one ran
/// the whole pipeline and parked a speaker-naming dialog about nothing;
/// measured on one machine: two recovered captures of 3 s and 14 s, each
/// with its own dialog. The threshold is `AppSettings.minimumAutoRecordingSeconds`.
///
/// Only automatic recordings are judged. A short manual recording is
/// deliberate (`RecordingSidecar.Trigger` exists for exactly this
/// distinction), a threshold of zero keeps everything, and a duration that
/// could not be measured keeps the recording: nothing is discarded on a
/// guess.
enum ShortRecordingPolicy {
    static func discards(
        trigger: RecordingSidecar.Trigger, duration: TimeInterval?, minimum: TimeInterval,
    ) -> Bool {
        guard trigger == .auto, minimum > 0, let duration else { return false }
        return duration < minimum
    }
}

/// The playing time of an audio file, read from its header. `nil` when the
/// file cannot be opened as audio, which callers treat as "unknown", never as
/// zero.
enum AudioFileDuration {
    static func seconds(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }
}
