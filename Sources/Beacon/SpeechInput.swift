import AVFoundation
import Speech

/// Push-to-talk speech recognition with Apple's recognizer, on-device when the Mac supports it.
@MainActor
final class SpeechInput {
    var onPartial: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finalWaiter: CheckedContinuation<Void, Never>?
    /// Bumped per recording; callbacks and timers from an earlier recording are ignored.
    private var session = 0
    private(set) var isRecording = false

    /// Whether audio stays on this Mac. False means Apple's server recognizer is used.
    var isOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func start() throws {
        cancel()
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Beacon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available right now."])
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // installTap raises an uncatchable exception on a 0-channel format (no microphone connected).
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "Beacon", code: 2, userInfo: [NSLocalizedDescriptionKey: "No microphone found. Plug one in and try again."])
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        latest = ""
        session += 1
        let mySession = session

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, mySession == self.session else { return }
                if let text { self.latest = text; self.onPartial?(text) }
                if isFinal || error != nil { self.resumeWaiter() }
            }
        }
    }

    /// Stops listening and returns the transcript. Waits briefly for the final result, then falls back
    /// to the last partial so a slow finaliser never adds dead air.
    func stop(maxWait: Duration = .milliseconds(700)) async -> String {
        guard isRecording else { return latest }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        let mySession = session

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finalWaiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: maxWait)
                guard mySession == self.session else { return }
                self.resumeWaiter()
            }
        }
        guard mySession == session else { return "" } // a new recording started while we waited
        task?.cancel()
        task = nil
        request = nil
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        if isRecording {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            isRecording = false
        }
        task?.cancel()
        task = nil
        request = nil
        session += 1
        resumeWaiter()
    }

    private func resumeWaiter() {
        finalWaiter?.resume()
        finalWaiter = nil
    }
}
