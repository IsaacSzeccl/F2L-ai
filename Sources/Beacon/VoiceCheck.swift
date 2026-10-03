import AVFoundation
import Foundation

/// A 5-second microphone and speech test: shows the level, the transcript, and what's wrong if anything.
@MainActor
final class VoiceCheck: ObservableObject {
    enum State { case idle, recording, done }

    @Published var state: State = .idle
    @Published var level: Float = 0
    @Published var heard = ""
    @Published var message = ""
    @Published var secondsLeft = 5
    @Published var canPlayBack = false
    /// Dictation is off in macOS, which blocks speech recognition entirely.
    @Published var needsDictation = false

    private let input = SpeechInput()
    private var player: AVAudioPlayer?
    private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("beacon-voice-check.caf")

    func run() async {
        guard state != .recording else { return }
        try? FileManager.default.removeItem(at: fileURL)
        canPlayBack = false
        needsDictation = false
        heard = ""
        message = ""
        level = 0
        input.recordingURL = fileURL
        input.onLevel = { [weak self] value in self?.level = value }
        input.onPartial = { [weak self] text in self?.heard = text }
        do {
            try input.start()
        } catch {
            message = error.localizedDescription
            state = .done
            return
        }
        state = .recording
        for remaining in stride(from: 5, to: 0, by: -1) {
            secondsLeft = remaining
            try? await Task.sleep(for: .seconds(1))
        }
        let transcript = await input.stop()
        input.recordingURL = nil
        heard = transcript
        level = 0
        let stats = input.stats
        let peak = String(format: "%.0f", stats.peakDB)
        let detail = "Mic: \(stats.inputName) · loudest \(peak) dBFS · \(stats.locale) · " + (stats.onDevice ? "on this Mac" : "Apple servers")
        message = (stats.diagnosis ?? "Looks good. If the words are still wrong, the cause is accent or noise, not the setup.")
            + "\n" + detail + (stats.errorText.map { "\nRecognizer: \($0)" } ?? "")
        needsDictation = stats.dictationDisabled
        canPlayBack = FileManager.default.fileExists(atPath: fileURL.path)
        state = .done
    }

    /// Plays back what the microphone captured, so you can hear if it's quiet, muffled or the wrong source.
    func playBack() {
        player = try? AVAudioPlayer(contentsOf: fileURL)
        player?.play()
    }
}
