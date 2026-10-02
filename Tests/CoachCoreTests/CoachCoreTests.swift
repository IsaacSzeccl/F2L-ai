import CoreGraphics
import Foundation
import Testing
@testable import CoachCore

private func context(elements: [ScreenElement] = [
    ScreenElement(id: "e1", role: "AXTextArea", label: "Ask anything", frame: CGRect(x: 300, y: 600, width: 500, height: 40)),
    ScreenElement(id: "e2", role: "AXButton", label: "Send prompt", frame: CGRect(x: 810, y: 605, width: 30, height: 30)),
]) -> ScreenContext {
    ScreenContext(appName: "Google Chrome", windowTitle: "ChatGPT", windowFrame: CGRect(x: 100, y: 50, width: 1000, height: 800), elements: elements)
}

@Suite struct PointerTests {
    @Test func parsesPointAt() {
        let call = ToolCall(id: "1", name: "point_at", argumentsJSON: #"{"element_id":"e2","caption":"Send"}"#)
        #expect(CoachTools.parse(call) == .element(id: "e2", caption: "Send"))
    }

    @Test func parsesRegionAndClear() {
        let region = ToolCall(id: "1", name: "point_at_region", argumentsJSON: #"{"box":[10,20,30,40]}"#)
        #expect(CoachTools.parse(region) == .region(box: [10, 20, 30, 40], caption: nil))
        #expect(CoachTools.parse(ToolCall(id: "2", name: "clear_pointer", argumentsJSON: "{}")) == .clear)
    }

    @Test func rejectsMalformedCalls() {
        #expect(CoachTools.parse(ToolCall(id: "1", name: "point_at", argumentsJSON: "{}")) == nil)
        #expect(CoachTools.parse(ToolCall(id: "1", name: "point_at_region", argumentsJSON: #"{"box":[1,2]}"#)) == nil)
        #expect(CoachTools.parse(ToolCall(id: "1", name: "click_it", argumentsJSON: "{}")) == nil)
    }

    @Test func resolvesKnownElementPrecisely() {
        let annotation = CoachTools.resolve(.element(id: "e2", caption: "Send"), in: context())
        #expect(annotation?.style == .precise)
        #expect(annotation?.rect == CGRect(x: 810, y: 605, width: 30, height: 30))
        #expect(annotation?.elementRole == "AXButton")
    }

    @Test func neverPointsAtAnInventedElement() {
        #expect(CoachTools.resolve(.element(id: "e99", caption: nil), in: context()) == nil)
    }

    @Test func regionFallbackIsApproximate() {
        let annotation = CoachTools.resolve(.region(box: [0, 0, 500, 500], caption: nil), in: context())
        #expect(annotation?.style == .approximate)
        #expect(annotation?.rect == CGRect(x: 100, y: 50, width: 500, height: 400))
        #expect(annotation?.caption == "Around here")
    }
}

@Suite struct GeometryTests {
    @Test func normalizedBoxClampsAndOrders() {
        let rect = Geometry.normalizedBoxToGlobal([1200, 500, 500, -10], windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rect == CGRect(x: 50, y: 0, width: 50, height: 50))
    }

    @Test func emptyBoxIsNil() {
        #expect(Geometry.normalizedBoxToGlobal([10, 10, 10, 50], windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
    }

    @Test func flipsTopLeftToAppKit() {
        let r = Geometry.topLeftToAppKit(CGRect(x: 10, y: 20, width: 30, height: 40), primaryScreenHeight: 1000)
        #expect(r == CGRect(x: 10, y: 940, width: 30, height: 40))
    }

    @Test func ringHasMinimumSize() {
        let ring = Geometry.ringRect(for: CGRect(x: 100, y: 100, width: 10, height: 10), padding: 4, minSide: 36)
        #expect(ring.width == 36 && ring.height == 36)
        #expect(ring.midX == 105 && ring.midY == 105)
    }
}

@Suite struct PromptTests {
    @Test func describesControlsWithIDs() {
        let text = PromptBuilder.describe(context())
        #expect(text.contains("e1 | text box | Ask anything"))
        #expect(text.contains("e2 | button | Send prompt"))
    }

    @Test func screenshotOnlyOnNewestMessage() {
        var ctx = context()
        ctx.screenshot = ImageAttachment(jpegBase64: "AAAA", pixelWidth: 10, pixelHeight: 10)
        let history = [ChatMessage(role: .user, text: "hi", image: ctx.screenshot), ChatMessage(role: .assistant, text: "hello")]
        let messages = PromptBuilder.messages(history: history, context: ctx, learnerText: "where do I type?", attachScreenshot: true)
        #expect(messages.first?.role == .system)
        #expect(messages.dropLast().allSatisfy { $0.image == nil })
        #expect(messages.last?.image != nil)
    }

    @Test func historyIsCapped() {
        let history = (0..<30).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, text: "\($0)") }
        let messages = PromptBuilder.messages(history: history, context: context(), learnerText: "x", attachScreenshot: false)
        #expect(messages.count == 1 + PromptBuilder.maxHistoryMessages + 1)
    }

    @Test func screenReferenceHeuristic() {
        #expect(ScreenReference.needsFreshFrame("where do I click?"))
        #expect(ScreenReference.needsFreshFrame("what's this"))
        #expect(!ScreenReference.needsFreshFrame("can you explain what a large language model actually is in simple terms"))
    }
}

@Suite struct StreamingTests {
    @Test func sseParserJoinsDataLines() {
        var parser = SSEParser()
        #expect(parser.feed(line: "event: message") == nil)
        #expect(parser.feed(line: "data: {\"a\":1}") == nil)
        #expect(parser.feed(line: "") == "{\"a\":1}")
        #expect(parser.feed(line: ": keep-alive") == nil)
    }

    @Test func openAIDecoderStreamsTextAndAssemblesToolCalls() throws {
        var decoder = OpenAIStreamDecoder()
        var events: [LLMEvent] = []
        let chunks = [
            #"{"choices":[{"delta":{"reasoning_content":"hmm"}}]}"#,
            #"{"choices":[{"delta":{"content":"Click "}}]}"#,
            #"{"choices":[{"delta":{"content":"here."}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"point_at","arguments":"{\"element_"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"id\":\"e2\"}"}}]}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "[DONE]",
        ]
        for chunk in chunks { events += try decoder.decode(payload: chunk) }
        #expect(events == [
            .text("Click "), .text("here."),
            .toolCall(ToolCall(id: "c1", name: "point_at", argumentsJSON: #"{"element_id":"e2"}"#)),
        ])
    }

    @Test func openAIDecoderAcceptsObjectArguments() throws {
        var decoder = OpenAIStreamDecoder()
        let events = try decoder.decode(payload: #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"clear_pointer","arguments":{}}}]},"finish_reason":"tool_calls"}]}"#)
        #expect(events == [.toolCall(ToolCall(id: "c1", name: "clear_pointer", argumentsJSON: "{}"))])
    }

    @Test func decodersSkipMalformedPayloads() throws {
        var openAI = OpenAIStreamDecoder()
        #expect(try openAI.decode(payload: "{not json") == [])
        var anthropic = AnthropicStreamDecoder()
        #expect(try anthropic.decode(payload: "{not json") == [])
    }

    @Test func openAIDecoderSurfacesErrors() {
        var decoder = OpenAIStreamDecoder()
        #expect(throws: LLMError.self) { try decoder.decode(payload: #"{"error":{"message":"bad key"}}"#) }
    }

    @Test func anthropicDecoder() throws {
        var decoder = AnthropicStreamDecoder()
        var events: [LLMEvent] = []
        let chunks = [
            #"{"type":"message_start","message":{}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi."}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t1","name":"point_at","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"element_id\":"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"e1\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            "[DONE]",
        ]
        for chunk in chunks { events += try decoder.decode(payload: chunk) }
        #expect(events == [.text("Hi."), .toolCall(ToolCall(id: "t1", name: "point_at", argumentsJSON: #"{"element_id":"e1"}"#))])
    }
}

@Suite struct RequestBodyTests {
    @Test func zaiDisablesThinkingAndSendsImage() throws {
        let settings = LLMSettings(provider: .zai, apiKey: "k")
        let messages = [ChatMessage(role: .user, text: "hi", image: ImageAttachment(jpegBase64: "QUJD", pixelWidth: 1, pixelHeight: 1))]
        let body = ZaiClient.body(settings: settings, messages: messages, tools: CoachTools.all)
        #expect(body["model"] as? String == "glm-4.6v")
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect(body["tool_stream"] == nil)
        #expect((body["tools"] as? [Any])?.count == 3)
        let content = ((body["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]]
        #expect((content?.first?["image_url"] as? [String: String])?["url"] == "data:image/jpeg;base64,QUJD")
        #expect(JSONSerialization.isValidJSONObject(body))
    }

    @Test func zaiGLM53UsesLowReasoning() {
        let body = ZaiClient.body(settings: LLMSettings(provider: .zai, model: "glm-5.3-flashx", apiKey: "k"), messages: [], tools: CoachTools.all)
        #expect((body["thinking"] as? [String: String])?["type"] == "enabled")
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["tool_stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == 2048)
    }

    @Test func anthropicSplitsSystemPrompt() {
        let messages = [ChatMessage(role: .system, text: "sys"), ChatMessage(role: .user, text: "hi")]
        let body = AnthropicClient.body(settings: LLMSettings(provider: .anthropic, apiKey: "k"), messages: messages, tools: CoachTools.all)
        #expect(body["system"] as? String == "sys")
        #expect((body["messages"] as? [Any])?.count == 1)
        #expect(JSONSerialization.isValidJSONObject(body))
    }

    @Test func missingKeyThrows() {
        #expect(throws: LLMError.missingAPIKey(provider: "z.ai")) {
            try ZaiClient(settings: LLMSettings(provider: .zai, apiKey: "")).makeRequest(messages: [], tools: [])
        }
    }
}

@Suite struct ChunkerTests {
    @Test func releasesWholeSentences() {
        var c = SentenceChunker(minimumLength: 10)
        var out = c.append("Great question to start with. Now click the ")
        #expect(out == ["Great question to start with."])
        out = c.append("box that says Ask anything.")
        #expect(out.isEmpty)
        #expect(c.finish() == "Now click the box that says Ask anything.")
    }

    @Test func stripsBracketedNotes() {
        var c = SentenceChunker(minimumLength: 1)
        #expect(c.append("Now press Send. [circled: Send prompt] ") == ["Now press Send."])
    }

    @Test func stripsMarkdown() {
        var c = SentenceChunker(minimumLength: 1)
        #expect(c.append("**Click** the `Send` button. ") == ["Click the Send button."])
    }
}

@Suite struct StepTrackerTests {
    @Test func reportsTypingAfterPauseThenSubmit() {
        var tracker = StepTracker(label: "Ask anything", role: "AXTextArea", frame: .zero, typingPause: 1)
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(tracker.observe(value: "What is", at: t0) == nil)
        #expect(tracker.tick(at: t0.addingTimeInterval(0.5)) == nil)
        #expect(tracker.observe(value: "What is AI?", at: t0.addingTimeInterval(0.6)) == nil)
        #expect(tracker.tick(at: t0.addingTimeInterval(1.7)) == .typed(label: "Ask anything", preview: "What is AI?"))
        #expect(tracker.tick(at: t0.addingTimeInterval(3)) == nil) // not reported twice
        #expect(tracker.observe(value: "", at: t0.addingTimeInterval(4)) == .submitted(label: "Ask anything"))
        #expect(tracker.isFinished)
    }

    @Test func submitDetectedEvenWithoutTypingPause() {
        var tracker = StepTracker(label: "Ask anything", role: "AXTextArea", frame: .zero, typingPause: 1.5)
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(tracker.observe(value: "Hi", at: t0) == nil)
        #expect(tracker.observe(value: "", at: t0.addingTimeInterval(0.3)) == .submitted(label: "Ask anything"))
    }

    @Test func clickInsideButton() {
        var tracker = StepTracker(label: "Send", role: "AXButton", frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        #expect(tracker.observeClick(at: CGPoint(x: 100, y: 100)) == nil)
        #expect(tracker.observeClick(at: CGPoint(x: 15, y: 15)) == .clicked(label: "Send"))
        #expect(tracker.observeClick(at: CGPoint(x: 15, y: 15)) == nil)
    }
}

@Suite struct SpikeScoringTests {
    @Test func scoresElementHitsAndMisses() {
        let c = SpikeCase(name: "send", question: "how do I send?", context: context(), expectedElementID: "e2")
        #expect(SpikeScoring.score(.element(id: "e2", caption: nil), for: c) == (true, true))
        #expect(SpikeScoring.score(.element(id: "e1", caption: nil), for: c) == (true, false))
        #expect(SpikeScoring.score(.element(id: "e9", caption: nil), for: c) == (false, false))
        #expect(SpikeScoring.score(nil, for: c) == (false, false))
    }
}
