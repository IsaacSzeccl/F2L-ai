import Foundation

public enum LLMProvider: String, Codable, Sendable, CaseIterable {
    case zai
    case anthropic

    public var displayName: String {
        switch self {
        case .zai: "z.ai (GLM)"
        case .anthropic: "Anthropic (Claude)"
        }
    }

    public var defaultModel: String {
        switch self {
        // Vision + native function calling, thinking can be switched off for latency.
        case .zai: "glm-4.6v"
        case .anthropic: "claude-sonnet-5-5"
        }
    }

    /// Small, cheap model for the background "what's on screen" summary.
    public var defaultSummaryModel: String {
        switch self {
        case .zai: "glm-4.6v-flashx"
        case .anthropic: "claude-haiku-4-5-20251001"
        }
    }
}

public struct LLMSettings: Sendable, Equatable {
    public var provider: LLMProvider
    public var model: String
    public var apiKey: String
    public var maxTokens: Int
    public var temperature: Double

    public init(provider: LLMProvider, model: String? = nil, apiKey: String, maxTokens: Int = 400, temperature: Double = 0.4) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
        self.apiKey = apiKey
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public protocol LLMClient: Sendable {
    func stream(messages: [ChatMessage], tools: [ToolDefinition]) -> AsyncThrowingStream<LLMEvent, Error>
}

public enum LLMClients {
    public static func make(_ settings: LLMSettings) -> any LLMClient {
        switch settings.provider {
        case .zai: ZaiClient(settings: settings)
        case .anthropic: AnthropicClient(settings: settings)
        }
    }
}

// MARK: - z.ai (OpenAI-compatible)

public struct ZaiClient: LLMClient {
    public static let endpoint = URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
    public let settings: LLMSettings

    public init(settings: LLMSettings) { self.settings = settings }

    public func stream(messages: [ChatMessage], tools: [ToolDefinition]) -> AsyncThrowingStream<LLMEvent, Error> {
        let request: URLRequest
        do {
            request = try makeRequest(messages: messages, tools: tools)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return SSEStreamer.run(request: request, decoder: OpenAIStreamDecoder()) { decoder, payload in
            try decoder.decode(payload: payload)
        }
    }

    public func makeRequest(messages: [ChatMessage], tools: [ToolDefinition]) throws -> URLRequest {
        guard !settings.apiKey.isEmpty else { throw LLMError.missingAPIKey(provider: "z.ai") }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(settings: settings, messages: messages, tools: tools))
        request.timeoutInterval = 60
        return request
    }

    public static func body(settings: LLMSettings, messages: [ChatMessage], tools: [ToolDefinition]) -> [String: Any] {
        var body: [String: Any] = [
            "model": settings.model,
            "stream": true,
            "max_tokens": settings.maxTokens,
            "temperature": settings.temperature,
            "messages": messages.map(encode),
        ]
        let model = settings.model.lowercased()
        if model.hasPrefix("glm-5.3") {
            // GLM-5.3 family cannot disable thinking; keep it as light as possible.
            body["thinking"] = ["type": "enabled"]
            body["reasoning_effort"] = "low"
            // Reasoning tokens may count against max_tokens; leave room so the spoken reply isn't cut to nothing.
            body["max_tokens"] = max(settings.maxTokens, 2048)
        } else {
            // A spoken coach can't afford hidden reasoning before the first word.
            body["thinking"] = ["type": "disabled"]
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
            body["tool_choice"] = "auto"
            if supportsToolStream(model) { body["tool_stream"] = true }
        }
        return body
    }

    static func supportsToolStream(_ model: String) -> Bool {
        model.hasPrefix("glm-5") || model == "glm-4.6" || model.hasPrefix("glm-4.7")
    }

    static func encode(_ message: ChatMessage) -> [String: Any] {
        guard let image = message.image else {
            return ["role": message.role.rawValue, "content": message.text]
        }
        return [
            "role": message.role.rawValue,
            "content": [
                ["type": "image_url", "image_url": ["url": image.dataURL]],
                ["type": "text", "text": message.text],
            ],
        ]
    }
}

// MARK: - Anthropic

public struct AnthropicClient: LLMClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public let settings: LLMSettings

    public init(settings: LLMSettings) { self.settings = settings }

    public func stream(messages: [ChatMessage], tools: [ToolDefinition]) -> AsyncThrowingStream<LLMEvent, Error> {
        let request: URLRequest
        do {
            request = try makeRequest(messages: messages, tools: tools)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return SSEStreamer.run(request: request, decoder: AnthropicStreamDecoder()) { decoder, payload in
            try decoder.decode(payload: payload)
        }
    }

    public func makeRequest(messages: [ChatMessage], tools: [ToolDefinition]) throws -> URLRequest {
        guard !settings.apiKey.isEmpty else { throw LLMError.missingAPIKey(provider: "Anthropic") }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(settings: settings, messages: messages, tools: tools))
        request.timeoutInterval = 60
        return request
    }

    public static func body(settings: LLMSettings, messages: [ChatMessage], tools: [ToolDefinition]) -> [String: Any] {
        let system = messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        var body: [String: Any] = [
            "model": settings.model,
            "max_tokens": settings.maxTokens,
            "temperature": settings.temperature,
            "stream": true,
            "messages": messages.filter { $0.role != .system }.map(encode),
        ]
        if !system.isEmpty { body["system"] = system }
        if !tools.isEmpty {
            body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }
        }
        return body
    }

    static func encode(_ message: ChatMessage) -> [String: Any] {
        var content: [[String: Any]] = []
        if let image = message.image {
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.jpegBase64]])
        }
        content.append(["type": "text", "text": message.text])
        return ["role": message.role.rawValue, "content": content]
    }
}

// MARK: - Shared SSE transport

enum SSEStreamer {
    static func run<Decoder: Sendable>(
        request: URLRequest,
        decoder initial: Decoder,
        decode: @escaping @Sendable (inout Decoder, String) throws -> [LLMEvent]
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 2000 { break }
                        }
                        throw LLMError.http(status: http.statusCode, body: body)
                    }
                    var decoder = initial
                    var parser = SSEParser()
                    // Split on raw "\n" bytes ourselves: `bytes.lines` also splits on U+2028/U+2029/U+0085,
                    // which can legally appear inside a JSON string, and it drops the blank event separators.
                    var line = Data()
                    for try await byte in bytes {
                        guard byte == 0x0A else { line.append(byte); continue }
                        try Task.checkCancellation()
                        if let payload = parser.feed(line: String(decoding: line, as: UTF8.self)) {
                            for event in try decode(&decoder, payload) { continuation.yield(event) }
                        }
                        line.removeAll(keepingCapacity: true)
                    }
                    if !line.isEmpty, let payload = parser.feed(line: String(decoding: line, as: UTF8.self)) {
                        for event in try decode(&decoder, payload) { continuation.yield(event) }
                    }
                    if let payload = parser.flush() {
                        for event in try decode(&decoder, payload) { continuation.yield(event) }
                    }
                    // Providers that end without [DONE] or finish_reason still get their tool calls out.
                    for event in try decode(&decoder, "[DONE]") where Self.isToolCall(event) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func isToolCall(_ event: LLMEvent) -> Bool {
        if case .toolCall = event { return true }
        return false
    }
}
