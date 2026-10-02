import Foundation

/// Splits a Server-Sent Events byte stream into `data:` payloads, one per event.
public struct SSEParser: Sendable {
    private var buffer = ""
    private var dataLines: [String] = []

    public init() {}

    /// Feed one line (without the trailing newline). Returns a payload when an event completes.
    public mutating func feed(line rawLine: String) -> String? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") { return nil } // comment / keep-alive
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }
        return nil
    }

    /// Emits any event left without a trailing blank line.
    public mutating func flush() -> String? {
        guard !dataLines.isEmpty else { return nil }
        defer { dataLines.removeAll() }
        return dataLines.joined(separator: "\n")
    }
}

/// Accumulates OpenAI-style streamed tool calls (fragments keyed by index) into whole calls.
public struct ToolCallAccumulator: Sendable {
    private struct Partial: Sendable {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var partials: [Int: Partial] = [:]

    public init() {}

    public mutating func add(index: Int, id: String?, name: String?, argumentsFragment: String?) {
        var partial = partials[index] ?? Partial()
        if let id, !id.isEmpty { partial.id = id }
        if let name, !name.isEmpty { partial.name = name }
        if let argumentsFragment { partial.arguments += argumentsFragment }
        partials[index] = partial
    }

    public mutating func drain() -> [ToolCall] {
        defer { partials.removeAll() }
        return partials.keys.sorted().compactMap { index in
            guard let p = partials[index], !p.name.isEmpty else { return nil }
            return ToolCall(id: p.id.isEmpty ? "call_\(index)" : p.id, name: p.name, argumentsJSON: p.arguments.isEmpty ? "{}" : p.arguments)
        }
    }
}

/// Decodes OpenAI-compatible chat-completion stream chunks (z.ai uses this format).
public struct OpenAIStreamDecoder: Sendable {
    private var tools = ToolCallAccumulator()

    public init() {}

    /// Returns events produced by one `data:` payload. Reasoning deltas are ignored: they are never spoken.
    /// Tool calls are emitted once their arguments are complete (on finish_reason or [DONE]).
    public mutating func decode(payload: String) throws -> [LLMEvent] {
        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
            return tools.drain().map(LLMEvent.toolCall)
        }
        // One malformed chunk must not kill a spoken reply: skip it.
        guard let object = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
            return []
        }
        if let error = object["error"] as? [String: Any] {
            throw LLMError.api(message: error["message"] as? String ?? "\(error)")
        }
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return [] }
        var events: [LLMEvent] = []
        if let delta = choice["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                events.append(.text(content))
            }
            for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let function = call["function"] as? [String: Any]
                tools.add(
                    index: (call["index"] as? NSNumber)?.intValue ?? 0,
                    id: call["id"] as? String,
                    name: function?["name"] as? String,
                    argumentsFragment: argumentString(function?["arguments"])
                )
            }
        }
        if let finish = choice["finish_reason"] as? String, !finish.isEmpty {
            events += tools.drain().map(LLMEvent.toolCall)
        }
        return events
    }

    /// Some providers send arguments as an object instead of a JSON string.
    private func argumentString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Decodes Anthropic Messages API stream events.
public struct AnthropicStreamDecoder: Sendable {
    private var openTools: [Int: (id: String, name: String, json: String)] = [:]

    public init() {}

    public mutating func decode(payload: String) throws -> [LLMEvent] {
        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" { return [] }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        let index = (object["index"] as? NSNumber)?.intValue ?? 0
        switch type {
        case "content_block_start":
            if let block = object["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                openTools[index] = (block["id"] as? String ?? "", block["name"] as? String ?? "", "")
            }
            return []
        case "content_block_delta":
            guard let delta = object["delta"] as? [String: Any] else { return [] }
            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                return [.text(text)]
            }
            if delta["type"] as? String == "input_json_delta", let part = delta["partial_json"] as? String {
                openTools[index]?.json += part
            }
            return []
        case "content_block_stop":
            guard let tool = openTools.removeValue(forKey: index) else { return [] }
            return [.toolCall(ToolCall(id: tool.id, name: tool.name, argumentsJSON: tool.json.isEmpty ? "{}" : tool.json))]
        case "error":
            let error = object["error"] as? [String: Any]
            throw LLMError.api(message: error?["message"] as? String ?? "unknown error")
        default:
            return []
        }
    }
}

public enum LLMError: Error, LocalizedError, Equatable {
    case missingAPIKey(provider: String)
    case http(status: Int, body: String)
    case api(message: String)

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider): "No API key set for \(provider). Add it in Settings."
        case let .http(status, body): "HTTP \(status): \(body.prefix(300))"
        case let .api(message): message
        }
    }
}
