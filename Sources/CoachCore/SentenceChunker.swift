import Foundation

/// Buffers streamed text and releases speakable chunks as soon as a sentence ends, so text-to-speech
/// can start on the first sentence while the model is still writing the rest.
public struct SentenceChunker: Sendable {
    private var buffer = ""
    /// Chunks shorter than this wait for more text, to avoid choppy one-word TTS requests.
    public var minimumLength: Int

    public init(minimumLength: Int = 24) {
        self.minimumLength = minimumLength
    }

    public mutating func append(_ text: String) -> [String] {
        buffer += text
        var chunks: [String] = []
        while let end = nextBoundary() {
            let chunk = String(buffer[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            if !chunk.isEmpty { chunks.append(Self.clean(chunk)) }
        }
        return chunks.filter { !$0.isEmpty }
    }

    public mutating func finish() -> String? {
        defer { buffer = "" }
        let rest = Self.clean(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        return rest.isEmpty ? nil : rest
    }

    /// Index just after a sentence terminator followed by whitespace, once enough text has accumulated.
    private func nextBoundary() -> String.Index? {
        var index = buffer.startIndex
        var count = 0
        while index < buffer.endIndex {
            let char = buffer[index]
            let next = buffer.index(after: index)
            count += 1
            if char == "\n", count >= 2 { return next }
            if ".!?".contains(char), count >= minimumLength, next < buffer.endIndex, buffer[next].isWhitespace {
                return next
            }
            index = next
        }
        return nil
    }

    /// Strips markdown the model might emit despite instructions, so it isn't read aloud.
    static func clean(_ text: String) -> String {
        // Drop bracketed stage directions such as "[circled: Send]" that models copy from history.
        var t = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        for token in ["**", "__", "`", "#"] { t = t.replacingOccurrences(of: token, with: "") }
        if t.hasPrefix("- ") || t.hasPrefix("* ") { t.removeFirst(2) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Wall-clock marks for one turn: learner stops talking → first model token → first audio.
public struct TurnLatency: Sendable {
    public var speechEnded: Date?
    public var requestSent: Date?
    public var firstToken: Date?
    public var firstAudio: Date?

    public init() {}

    public func summary() -> String {
        func ms(_ a: Date?, _ b: Date?) -> String {
            guard let a, let b else { return "–" }
            return "\(Int(b.timeIntervalSince(a) * 1000))ms"
        }
        return "speech→request \(ms(speechEnded, requestSent)), request→first token \(ms(requestSent, firstToken)), "
            + "first token→first audio \(ms(firstToken, firstAudio)), TOTAL speech→audio \(ms(speechEnded, firstAudio))"
    }
}
