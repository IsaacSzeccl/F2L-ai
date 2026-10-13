@preconcurrency import AVFoundation
import CoachCore
import Speech

/// Start/finish dictation with Apple's recognizer (on-device when available). Mirrors PushToTalkInput on Windows:
/// the words land in the composer for review before sending.
@MainActor
final class DictationInput {
    var onTranscript: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var recognizerLanguage = ""

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var session = 0
    private var finalWaiter: CheckedContinuation<Void, Never>?
    private(set) var isListening = false

    /// Asks for microphone and speech permission the first time. Returns an error message, or nil when ready.
    func prepare() async -> String? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "speech recognition is off for F2L in System Settings › Privacy & Security › Speech Recognition"
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "microphone access is off for F2L in System Settings › Privacy & Security › Microphone"
        }
        return nil
    }

    func start() throws {
        cancel()
        // Prefer the display language, like Windows; fall back to US English.
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { throw ScreenCaptureError(message: "speech recognition isn't available right now") }
        self.recognizer = recognizer
        recognizerLanguage = Locale.current.localizedString(forIdentifier: recognizer.locale.identifier) ?? recognizer.locale.identifier
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // installTap raises an uncatchable exception on a 0-channel format (no microphone connected).
        guard format.channelCount > 0, format.sampleRate > 0 else { throw ScreenCaptureError(message: "no microphone found") }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        latest = ""
        session += 1
        let mySession = session
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        try engine.start()
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            let failure = error.map { ($0 as NSError).localizedDescription }
            Task { @MainActor in
                guard let self, mySession == self.session else { return }
                if let text { self.latest = text; self.onTranscript?(text) }
                if let failure, self.isListening, self.latest.isEmpty { self.onFailure?(failure) }
                if done { self.finalWaiter?.resume(); self.finalWaiter = nil }
            }
        }
    }

    /// Stops listening and returns the transcript, waiting up to two seconds for the final result.
    func stop() async -> String {
        guard isListening else { return latest }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        let mySession = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finalWaiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard mySession == self.session else { return }
                self.finalWaiter?.resume()
                self.finalWaiter = nil
            }
        }
        task?.cancel()
        task = nil
        request = nil
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        if isListening {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            isListening = false
        }
        task?.cancel()
        task = nil
        request = nil
        session += 1
        finalWaiter?.resume()
        finalWaiter = nil
    }
}
