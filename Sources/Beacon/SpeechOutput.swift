import AVFoundation
import Foundation

/// Speaks the coach's replies sentence by sentence. ElevenLabs streaming PCM is the main voice;
/// Apple's built-in synthesizer takes over automatically when there is no key or the network fails.
@MainActor
final class SpeechOutput: NSObject {
    var onFirstAudio: (() -> Void)?
    var onFinished: (() -> Void)?

    private static let sampleRate = 22050.0
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    private let synthesizer = AVSpeechSynthesizer()

    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var pendingBuffers = 0
    /// Utterances handed to the system synthesizer and not yet finished. Counted by hand because
    /// `AVSpeechSynthesizer.isSpeaking` lags behind `speak()` and `didFinish`.
    private var liveUtterances = Set<ObjectIdentifier>()
    /// Bumped on every stop(); late callbacks from an older generation are ignored.
    private var generation = 0
    private var reportedFirstAudio = false
    private var synthesizerFallbackActive = false
    private var configObserver: Any?

    override init() {
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        synthesizer.delegate = self
        // A route change (e.g. Bluetooth headphones switching profile when the mic opens) stops the engine
        // and drops scheduled buffers without calling their completions. Reset rather than hang in "speaking".
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.worker != nil || self.pendingBuffers > 0 else { return }
                Log.voice.info("Audio route changed mid-reply; resetting playback")
                self.stop()
                self.onFinished?()
            }
        }
    }

    var isSpeaking: Bool { !queue.isEmpty || worker != nil || pendingBuffers > 0 || !liveUtterances.isEmpty }

    /// Starts a new reply: resets first-audio tracking and retries ElevenLabs.
    func beginReply() {
        reportedFirstAudio = false
        synthesizerFallbackActive = false
    }

    func enqueue(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        queue.append(text)
        if worker == nil { startWorker() }
    }

    /// Barge-in: silence immediately and drop everything queued.
    func stop() {
        generation += 1
        queue.removeAll()
        worker?.cancel()
        worker = nil
        player.stop()
        pendingBuffers = 0
        liveUtterances.removeAll()
        synthesizerFallbackActive = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Worker

    private func startWorker() {
        let myGeneration = generation
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, myGeneration == self.generation, !self.queue.isEmpty {
                let sentence = self.queue.removeFirst()
                await self.speak(sentence, generation: myGeneration)
            }
            guard let self, myGeneration == self.generation else { return }
            self.worker = nil
            self.checkFinished()
        }
    }

    private func speak(_ sentence: String, generation myGeneration: Int) async {
        let key = Secrets.read(.elevenLabs)
        guard !key.isEmpty, !synthesizerFallbackActive else {
            speakWithSystemVoice(sentence)
            return
        }
        var scheduledAny = false
        do {
            try await streamElevenLabs(sentence, apiKey: key, generation: myGeneration, scheduledAny: &scheduledAny)
        } catch {
            // stop() cancels the request: URLSession reports that as URLError.cancelled, not CancellationError.
            let cancelled = Task.isCancelled || myGeneration != generation || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            if cancelled { return }
            Log.voice.error("ElevenLabs failed, using system voice: \(error.localizedDescription, privacy: .public)")
            // Stay on the system voice for the rest of this reply so the voice doesn't flip back and forth.
            synthesizerFallbackActive = true
            // If part of this sentence is already playing, don't read it again over the top.
            if !scheduledAny { speakWithSystemVoice(sentence) }
        }
    }

    private func streamElevenLabs(_ text: String, apiKey: String, generation myGeneration: Int, scheduledAny: inout Bool) async throws {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(Preferences.voiceID)/stream")!
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_22050")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": Preferences.ttsModel,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75],
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = Data()
            for try await byte in bytes { body.append(byte); if body.count > 1000 { break } }
            throw NSError(domain: "ElevenLabs", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(String(decoding: body, as: UTF8.self))"])
        }

        if !engine.isRunning { try engine.start() }
        // ~0.1s of audio per buffer: small enough to start fast, big enough to avoid underruns.
        let chunkBytes = 4410
        var pending = Data()
        pending.reserveCapacity(chunkBytes * 2)
        for try await byte in bytes {
            pending.append(byte)
            if pending.count >= chunkBytes {
                try Task.checkCancellation()
                guard myGeneration == generation else { return }
                schedule(pcm16: pending)
                scheduledAny = true
                pending.removeAll(keepingCapacity: true)
            }
        }
        if pending.count >= 2, myGeneration == generation {
            schedule(pcm16: pending)
            scheduledAny = true
        }
    }

    private func schedule(pcm16 data: Data) {
        let sampleCount = data.count / 2
        // A route change can stop the engine mid-download; play() on a stopped engine is an uncatchable exception.
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        guard sampleCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let out = buffer.floatChannelData![0]
        data.withUnsafeBytes { raw in
            for i in 0..<sampleCount {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                out[i] = Float(sample) / 32768
            }
        }
        pendingBuffers += 1
        let myGeneration = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, myGeneration == self.generation else { return }
                self.pendingBuffers -= 1
                self.checkFinished()
            }
        }
        if !player.isPlaying { player.play() }
        markFirstAudio()
    }

    private func speakWithSystemVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        liveUtterances.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
        markFirstAudio()
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        // Ignore utterances from before the last stop().
        guard liveUtterances.remove(id) != nil else { return }
        checkFinished()
    }

    private func markFirstAudio() {
        guard !reportedFirstAudio else { return }
        reportedFirstAudio = true
        onFirstAudio?()
    }

    private func checkFinished() {
        guard !isSpeaking else { return }
        onFinished?()
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // stop() already zeroed the count; ignore cancellations it caused.
    }
}
