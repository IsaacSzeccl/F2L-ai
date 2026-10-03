import AudioToolbox
import AVFoundation
import Speech

/// What happened during one recording: enough to tell a silent microphone from a recognition problem.
struct SpeechStats {
    var inputName = "?"
    var locale = "?"
    var onDevice = false
    /// Loudest sample, in dBFS (0 = full scale, -120 = silence).
    var peakDB: Float = -120
    var seconds: Double = 0
    var partials = 0
    var finalText = ""
    var errorText: String?

    /// macOS refuses to run speech recognition (even on-device) while Dictation is switched off.
    var dictationDisabled: Bool { errorText?.contains("kLSRErrorDomain 201") == true }

    static let dictationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    /// A plain-English reason the transcript came out empty or wrong, or nil if it looks healthy.
    var diagnosis: String? {
        if dictationDisabled { return "Turn on Dictation: System Settings, then Keyboard, then Dictation. macOS needs it for speech." }
        if peakDB < -60 { return "The microphone (\(inputName)) is silent. Choose another one in Settings." }
        if peakDB < -40 { return "Very quiet from \(inputName). Speak closer or turn the input volume up." }
        if peakDB > -1 { return "Too loud from \(inputName); the sound is distorted. Turn the input volume down." }
        if finalText.isEmpty { return "The microphone works (\(inputName)), but no words were recognised. Try another language or turn off 'keep speech on this Mac' in Settings." }
        return nil
    }
}

/// Push-to-talk speech recognition with Apple's recognizer, on-device unless Settings says otherwise.
@MainActor
final class SpeechInput {
    var onPartial: ((String) -> Void)?
    /// Microphone loudness 0...1 while recording (for the level meter).
    var onLevel: ((Float) -> Void)?
    /// If set, the raw audio is saved here (voice check only, on explicit request).
    var recordingURL: URL?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finalWaiter: CheckedContinuation<Void, Never>?
    /// Bumped per recording; callbacks and timers from an earlier recording are ignored.
    private var session = 0
    private var startedAt = Date()
    private(set) var isRecording = false
    private(set) var stats = SpeechStats()

    /// Words the recognizer often gets wrong without a hint.
    private static let vocabulary = [
        "ChatGPT", "Gemini", "Copilot", "Claude", "OpenAI", "Beacon", "prompt", "Google Docs", "Google Sheets",
        "Gmail", "Microsoft Word", "Excel", "AI", "artificial intelligence", "screenshot",
    ]

    func start() throws {
        cancel()
        let localeID = Preferences.speechLocale
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw NSError(domain: "Beacon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available right now."])
        }
        let wantsOnDevice = Preferences.speechOnDeviceOnly
        if wantsOnDevice, !recognizer.supportsOnDeviceRecognition {
            throw NSError(domain: "Beacon", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "On-device speech isn't available for \(localeID). Pick another language, or turn off 'keep speech on this Mac' in Settings."])
        }

        // Choose the microphone first: the input format depends on it.
        var chosen = AudioDevices.defaultInput()
        if let uid = Preferences.inputDeviceUID, let device = AudioDevices.device(forUID: uid) {
            chosen = device
            var deviceID = device.deviceID
            if let audioUnit = engine.inputNode.audioUnit {
                let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                  &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
                if status != noErr { Log.voice.error("Could not select microphone \(device.name, privacy: .public): \(status)") }
            }
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
        request.taskHint = .dictation
        request.contextualStrings = Self.vocabulary
        request.requiresOnDeviceRecognition = wantsOnDevice
        self.request = request
        latest = ""
        session += 1
        let mySession = session

        stats = SpeechStats(inputName: chosen?.name ?? "default input", locale: recognizer.locale.identifier, onDevice: wantsOnDevice)
        startedAt = Date()
        let rateText = String(format: "%.0f", format.sampleRate)
        Log.voice.notice("Listening: mic=\(self.stats.inputName, privacy: .public) \(rateText, privacy: .public)Hz x\(format.channelCount) locale=\(self.stats.locale, privacy: .public) onDevice=\(wantsOnDevice)")

        let file = recordingURL.flatMap { try? AVAudioFile(forWriting: $0, settings: format.settings) }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            try? file?.write(from: buffer)
            var peak: Float = 0
            if let channel = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
            }
            Task { @MainActor in self?.noteLevel(peak, session: mySession) }
        }
        engine.prepare()
        try engine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error as NSError?
            Task { @MainActor in
                guard let self, mySession == self.session else { return }
                if let text {
                    self.latest = text
                    self.stats.partials += 1
                    self.onPartial?(text)
                }
                if let failure {
                    // 1110 = "no speech detected", which is normal when nothing was said.
                    self.stats.errorText = "\(failure.domain) \(failure.code): \(failure.localizedDescription)"
                    Log.voice.error("Recognizer error \(failure.domain, privacy: .public) \(failure.code): \(failure.localizedDescription, privacy: .public)")
                }
                if isFinal || failure != nil { self.resumeWaiter() }
            }
        }
    }

    /// Stops listening and returns the transcript. Keeps recording a moment after the key is released so
    /// the last word isn't clipped, then waits for the final result, falling back to the last partial.
    func stop(tail: Duration = .milliseconds(250), maxWait: Duration = .milliseconds(1500)) async -> String {
        guard isRecording else { return latest }
        let mySession = session
        try? await Task.sleep(for: tail)
        guard mySession == session, isRecording else { return "" }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

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
        let transcript = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        stats.seconds = Date().timeIntervalSince(startedAt)
        stats.finalText = transcript
        let peak = String(format: "%.0f", stats.peakDB)
        let seconds = String(format: "%.1f", stats.seconds)
        Log.voice.notice("Heard (\(seconds, privacy: .public)s, peak \(peak, privacy: .public) dBFS, \(self.stats.partials) partials): \"\(transcript, privacy: .public)\"")
        return transcript
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

    private func noteLevel(_ peak: Float, session mySession: Int) {
        guard mySession == session else { return }
        let db = peak > 0 ? 20 * log10(peak) : -120
        stats.peakDB = max(stats.peakDB, db)
        onLevel?(max(0, min(1, (db + 60) / 60)))
    }

    private func resumeWaiter() {
        finalWaiter?.resume()
        finalWaiter = nil
    }
}
