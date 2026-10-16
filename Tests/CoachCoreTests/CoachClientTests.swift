import Foundation
import Testing
@testable import CoachCore

/// Builds a chat-completions body the way DeepSeek returns it.
func completion(_ content: Any?) -> Data {
    var message: [String: Any] = ["role": "assistant"]
    message["content"] = content ?? NSNull()
    return try! JSONSerialization.data(withJSONObject: ["model": "deepseek-flash", "choices": [["index": 0, "finish_reason": "stop", "message": message]]])
}

func jsonObject(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

@Suite struct RequestBody {
    @Test func earlierRepliesAreSentInTheJSONShapeTheModelAnswersIn() throws {
        // Plain-text replies in the history made DeepSeek's JSON mode answer with only spaces.
        let body = jsonObject(try CoachClient.requestBody(
            question: "Hey please teach me how to build a pi chart in excel",
            history: [("user", "Hey what can you see"), ("assistant", "I can't see your screen right now.")], jpeg: nil))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 4)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == CoachClient.teachingPrompt)
        #expect(messages[1]["content"] as? String == "Hey what can you see")
        #expect(messages[2]["content"] as? String == #"{"reply":"I can't see your screen right now.","target":null}"#)
        #expect(messages[3]["content"] as? String == "Hey please teach me how to build a pi chart in excel")
        #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
        #expect(body["model"] as? String == "deepseek-flash")
        #expect(body["max_tokens"] as? Int == 1400)
        #expect(body["stream"] as? Bool == false)
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
    }

    @Test func historyRepliesKeepQuotesNewlinesAndNonLatinText() throws {
        let reply = "Type \"=SUM(B2:B10)\" then press Enter.\n\n圈出 A1 / B1"
        // Byte-for-byte what Windows sends (CoachClient.HistoryReply).
        #expect(CoachClient.historyReply(reply) == #"{"reply":"Type \"=SUM(B2:B10)\" then press Enter.\n\n圈出 A1 / B1","target":null}"#)
        #expect(jsonObject(Data(CoachClient.historyReply(reply).utf8))["reply"] as? String == reply)
    }

    @Test func screenshotIsAttachedAsAHighDetailJPEGPart() throws {
        let body = jsonObject(try CoachClient.requestBody(question: "What is this?", history: [], jpeg: Data([0xFF, 0xD8, 0xFF])))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(parts[0]["text"] as? String == "What is this?")
        let image = try #require(parts[1]["image_url"] as? [String: String])
        #expect(image["url"] == "data:image/jpeg;base64,/9j/")
        #expect(image["detail"] == "high")
    }

    @Test func historyIsCappedAtTwentyMessagesAndRetryDropsJSONMode() throws {
        let history = (0..<30).map { ($0 % 2 == 0 ? "user" : "assistant", "message \($0)") }
        let body = jsonObject(try CoachClient.requestBody(question: "q", history: history, jpeg: Data(), jsonMode: false))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 22) // system + 20 history + question
        #expect(messages[1]["content"] as? String == "message 10")
        #expect(body["response_format"] == nil)
        #expect(messages.last?["content"] as? String == "q") // an empty image is not attached
    }
}

@Suite struct ResponseParsing {
    @Test func readsReplyAndTarget() throws {
        let answer = try #require(try CoachClient.parse(responseBody: completion(
            #"{"reply":"Sure! Click Insert, then Pie.","target":{"left":100,"top":20,"right":180,"bottom":60,"label":"Insert"}}"#)))
        #expect(answer.reply == "Click Insert, then Pie.")
        #expect(answer.target == ScreenTarget(left: 100, top: 20, right: 180, bottom: 60, label: "Insert"))
    }

    @Test(arguments: ["", "     ", "\n\n", #"{"target":null}"#, #"{"reply":"   ","target":null}"#, #"{"reply":42}"#])
    func blankOrMissingRepliesAskForARetry(content: String) throws {
        #expect(try CoachClient.parse(responseBody: completion(content)) == nil)
    }

    @Test func nullContentAsksForARetry() throws {
        #expect(try CoachClient.parse(responseBody: completion(nil)) == nil)
    }

    @Test func plainTextIsAcceptedWhenJSONModeIsOff() throws {
        let answer = try #require(try CoachClient.parse(responseBody: completion("Select A1.\n\nThen type a heading.")))
        #expect(answer.reply == "Select A1.\n\nThen type a heading.")
        #expect(answer.target == nil)
    }

    @Test(arguments: ["```json\n{\"reply\":\"Open Insert.\",\"target\":null}\n```", "```{\"reply\":\"Open Insert.\",\"target\":null}```"])
    func codeFencesAreRemoved(content: String) throws {
        #expect(try CoachClient.parse(responseBody: completion(content))?.reply == "Open Insert.")
    }

    @Test func contentPartsAreJoined() throws {
        let parts: [[String: Any]] = [["type": "text", "text": #"{"reply":"Open"#], ["type": "text", "text": "\n"],
                                      ["type": "image"], ["type": "text", "text": #"Insert.","target":null}"#]]
        #expect(try CoachClient.parse(responseBody: completion(parts))?.reply == "Open Insert.")
    }

    @Test(arguments: [Data("not json".utf8), Data(#"{"choices":[]}"#.utf8), Data(#"{"choices":[{"message":{"role":"assistant"}}]}"#.utf8),
                      completion(#"{"reply":"cut off"#)])
    func unreadableResponsesSayso(body: Data) {
        do {
            _ = try CoachClient.parse(responseBody: body)
            Issue.record("expected an unreadable-response error")
        } catch {
            #expect((error as? CoachRequestError)?.message == Provider.deepSeek.unreadable())
        }
    }
}

@Suite struct TargetParsing {
    func target(_ json: String) -> ScreenTarget? {
        CoachClient.parseTarget(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    @Test func cellTargetsAreNormalised() {
        #expect(target(#"{"cell":"$b$12","label":"anything"}"#) == ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: "B12", cell: "B12"))
        #expect(target(#"{"cell":"Sheet1!A1"}"#) == nil)
        #expect(target(#"{"cell":"Sheet1!A1","left":1,"top":1,"right":5,"bottom":5}"#) == nil) // an invalid cell never falls back to a rectangle
        #expect(target(#"{"cell":"A1:B2","left":1,"top":1,"right":5,"bottom":5}"#) == ScreenTarget(left: 1, top: 1, right: 5, bottom: 5, label: "A1:B2", cell: "A1"))
    }

    @Test func rectanglesMustBeWholeNumbersInsideTheScreenshot() {
        #expect(target(#"{"left":0,"top":0,"right":700,"bottom":700}"#)?.label == "Next step")
        #expect(target(#"{"left":10.0,"top":0,"right":20,"bottom":20}"#) == nil)
        #expect(target(#"{"left":true,"top":0,"right":20,"bottom":20}"#) == nil)
        #expect(target(#"{"left":"10","top":0,"right":20,"bottom":20}"#) == nil)
        #expect(target(#"{"left":-1,"top":0,"right":20,"bottom":20}"#) == nil)
        #expect(target(#"{"left":0,"top":0,"right":1001,"bottom":20}"#) == nil)
        #expect(target(#"{"left":20,"top":0,"right":20,"bottom":20}"#) == nil)
        #expect(target(#"{"left":0,"top":0,"right":701,"bottom":20}"#) == nil)
        #expect(target(#"{"left":0,"top":0,"right":10,"bottom":10,"label":"  A very long label that keeps going and going  "}"#)?.label
            == "A very long label that keeps going a")
        #expect(target("null") == nil)
    }
}

@Suite struct ProviderErrors {
    @Test func errorBodiesNeverExposeCredentials() {
        let credential = "sk-" + String(repeating: "a1", count: 24)
        let body = Data("{\"error\":{\"message\":\"Rejected credential: \(credential)\"}}".utf8)
        for provider in Provider.allCases {
            for status in [301, 307, 400, 401, 403, 422, 500, 502] {
                let message = CoachClient.explain(status: status, body: body, provider: provider)
                #expect(!message.contains(credential))
                #expect(!message.contains("Rejected credential:"))
            }
        }
    }

    @Test func redirectsAreRejected() {
        let destination = URL(string: "https://example.invalid/collect")!
        let request = URLRequest(url: destination)
        let response = HTTPURLResponse(url: Provider.claude.endpoint, statusCode: 307,
                                       httpVersion: nil, headerFields: ["Location": destination.absoluteString])!
        let session = CoachClient.defaultSession
        let delegate = session.delegate as? ProviderSessionDelegate
        #expect(delegate != nil)
        let task = session.dataTask(with: request)
        defer { task.cancel() }
        var called = false
        delegate?.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
            called = true
            #expect($0 == nil)
        }
        #expect(called)
    }

    @Test func statusCodesHaveSpecificMessages() {
        #expect(CoachClient.explain(status: 401, body: Data()).hasPrefix("DeepSeek rejected the configured API key (401)."))
        #expect(CoachClient.explain(status: 402, body: Data()).contains("no available balance"))
        #expect(CoachClient.explain(status: 422, body: Data(#"{"error":{"message":"bad\r\nthing"}}"#.utf8))
            == "DeepSeek rejected the request (422). Check the selected model and request settings, then try again.")
        #expect(CoachClient.explain(status: 500, body: Data("oops".utf8))
            == "DeepSeek returned an error (500). Check the local F2L status and try again.")
    }
}

/// Answers each request from a queue of canned responses and records what was sent.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [(Int, Data)] = []
    nonisolated(unsafe) private static var sent: [[String: Any]] = []

    static func reset(_ responses: [(Int, Data)]) { lock.withLock { queue = responses; sent = [] } }
    static var requests: [[String: Any]] { lock.withLock { sent } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let (status, data) = Self.lock.withLock {
            Self.sent.append(jsonObject(body))
            return Self.queue.isEmpty ? (500, Data()) : Self.queue.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct AnswerRetries {
    let client = CoachClient(apiKey: { "sk-test" }, session: StubURLProtocol.session)
    let history: [(role: String, content: String)] = [("user", "Hey what can you see"), ("assistant", "I can't see your screen right now.")]

    @Test func starterPlanUsesSeparateTextOnlyRequest() async throws {
        StubURLProtocol.reset([(200, completion(starterPlanFixture))])
        var p = LearnerProfile(); p.name = "Private name"; p.role = "Operations"
        let plan = try await client.starterPlan(for: p)
        #expect(plan.source == "DeepSeek")
        let requests = StubURLProtocol.requests
        #expect(requests.count == 1)
        let messages = try #require(requests.first?["messages"] as? [[String: Any]])
        #expect(messages.count == 2 && messages.first?["content"] as? String == StarterPlan.systemPrompt)
        let question = try #require(messages.last?["content"] as? String)
        #expect(question.contains("Operations") && !question.contains("Private name"))
    }

    @Test func missingPlanKeyNeverCallsTheNetwork() async {
        StubURLProtocol.reset([])
        await #expect(throws: CoachRequestError.self) {
            try await CoachClient(apiKey: { "" }, session: StubURLProtocol.session).starterPlan(for: LearnerProfile())
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func blankJSONModeReplyIsAskedAgainWithoutJSONMode() async throws {
        StubURLProtocol.reset([(200, completion("       ")), (200, completion(#"{"reply":"Select your data, then choose Insert › Pie.","target":null}"#))])
        let answer = try await client.answer(question: "Hey please teach me how to build a pi chart in excel", history: history, jpeg: nil)
        #expect(answer.reply == "Select your data, then choose Insert › Pie.")
        let requests = StubURLProtocol.requests
        #expect(requests.count == 2)
        #expect(requests[0]["response_format"] != nil)
        #expect(requests[1]["response_format"] == nil)
    }

    @Test func unreadableReplyIsAskedAgain() async throws {
        StubURLProtocol.reset([(200, completion(#"{"reply":"cut"#)), (200, completion("Open Insert, then pick Pie."))])
        let answer = try await client.answer(question: "pie chart?", history: [], jpeg: nil)
        #expect(answer.reply == "Open Insert, then pick Pie.")
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test func twoBlankRepliesBecomeAnErrorInsteadOfAReply() async {
        StubURLProtocol.reset([(200, completion("  ")), (200, completion(""))])
        do {
            _ = try await client.answer(question: "pie chart?", history: history, jpeg: nil)
            Issue.record("expected an error")
        } catch {
            #expect((error as? CoachRequestError)?.message == Provider.deepSeek.noReply())
        }
    }

    @Test func providerErrorsAreNotRetried() async {
        StubURLProtocol.reset([(401, Data(#"{"error":{"message":"invalid key"}}"#.utf8)), (200, completion("unused"))])
        do {
            _ = try await client.answer(question: "pie chart?", history: [], jpeg: nil)
            Issue.record("expected an error")
        } catch {
            #expect((error as? CoachRequestError)?.message.hasPrefix("DeepSeek rejected the configured API key (401).") == true)
        }
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func missingKeyNeverCallsTheNetwork() async {
        StubURLProtocol.reset([])
        do {
            _ = try await CoachClient(apiKey: { "" }, session: StubURLProtocol.session).answer(question: "q", history: [], jpeg: nil)
            Issue.record("expected an error")
        } catch {
            #expect((error as? CoachRequestError)?.message == Provider.deepSeek.notConfigured())
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}

/// Opt-in check against the real service with the key in local.settings.json:
///   F2L_LIVE_DEEPSEEK=1 scripts/test.sh
/// Replays the conversation that used to end in "I couldn't form a reply just now".
@Suite(.enabled(if: ProcessInfo.processInfo.environment["F2L_LIVE_DEEPSEEK"] == "1"))
struct LiveDeepSeek {
    @Test func answersAFollowUpQuestion() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let key = LocalSettings.read(.deepSeek, file: LocalSettings.settingsFile(startingAt: repository))
        try #require(!key.isEmpty, "No DeepSeekApiKey found")
        let client = CoachClient(apiKey: { key })
        let history: [(role: String, content: String)] = [
            ("user", "Hey what can you see"),
            ("assistant", "I can't see your screen right now because no screenshot came through. Share one and I'll tell you what's on it and what to do next."),
        ]
        for _ in 0..<3 {
            let answer = try await client.answer(question: "Hey please teach me how to build a pi chart in excel", history: history, jpeg: nil)
            #expect(answer.reply.count > 20)
            #expect(!answer.reply.contains("couldn't form a reply"))
        }
    }
}

@Suite struct SwitchingProviders {
    func body(_ provider: Provider, model: String? = nil, jpeg: Data? = Data([1, 2, 3])) throws -> [String: Any] {
        let data = try CoachClient.requestBody(question: "Where is Fill?", history: [("user", "Hi"), ("assistant", "Hello")], jpeg: jpeg,
                                               provider: provider, model: model)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theProviderAndModelComeFromTheSettingsFile() throws {
        try withScratch { folder in
            let file = folder.appendingPathComponent("local.settings.json")
            try Data(#"{"Provider":"Claude","ClaudeModel":"claude-sonnet-5-5","ClaudeApiKey":"k"}"#.utf8).write(to: file)
            #expect(LocalSettings.provider(file: file) == .claude)
            #expect(LocalSettings.model(for: .claude, file: file) == "claude-sonnet-5-5")
            #expect(LocalSettings.model(for: .gemini, file: file) == "")
            #expect(LocalSettings.setProvider(.gemini, file: file))
            #expect(LocalSettings.provider(file: file) == .gemini)
            // Switching keeps every key and model already in the file.
            let kept = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
            #expect(kept["ClaudeApiKey"] == "k" && kept["ClaudeModel"] == "claude-sonnet-5-5")
            // Settings saves a key next to the others, readable only by this user, and an empty one removes it.
            #expect(LocalSettings.setKey(.gemini, " g-key \n", file: file))
            #expect(LocalSettings.read(.gemini, environment: [:], file: file, keychain: { _ in "" }) == "g-key")
            #expect(LocalSettings.read(.claude, environment: [:], file: file, keychain: { _ in "" }) == "k")
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
            #expect(LocalSettings.setKey(.gemini, "", file: file))
            #expect(LocalSettings.read(.gemini, environment: [:], file: file, keychain: { _ in "" }) == "")
            #expect(LocalSettings.provider(file: file) == .gemini)
            try Data(#"{"Provider":"chatgpt"}"#.utf8).write(to: file)
            #expect(LocalSettings.provider(file: file) == .openAI)
            try Data(#"{"Provider":"something else"}"#.utf8).write(to: file)
            #expect(LocalSettings.provider(file: file) == .deepSeek)
        }
    }

    @Test func claudeUsesTheMessagesFormat() throws {
        let claude = try body(.claude)
        #expect(claude["model"] as? String == "claude-opus-5-5")
        #expect(claude["system"] as? String == CoachClient.teachingPrompt)
        let messages = try #require(claude["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let last = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(last.first?["type"] as? String == "image" && last.last?["type"] as? String == "text")
        #expect(claude["response_format"] == nil && claude["temperature"] == nil)
        let reply = try CoachClient.parse(responseBody: Data(#"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"reply\":\"Click Fill.\",\"steps\":[],\"target\":null}"}],"stop_reason":"end_turn"}"#.utf8), provider: .claude)
        #expect(reply?.reply == "Click Fill.")
        #expect(throws: CoachRequestError.self) {
            try CoachClient.parse(responseBody: Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8), provider: .claude)
        }
    }

    @Test func openAIStyleProvidersShareOneFormat() throws {
        for provider in [Provider.openAI, .gemini, .glm, .deepSeek] {
            let request = try body(provider)
            let messages = try #require(request["messages"] as? [[String: Any]])
            #expect(messages.first?["role"] as? String == "system")
            #expect((request["response_format"] as? [String: String])?["type"] == "json_object")
        }
        let openAI = try body(.openAI)
        #expect(openAI["temperature"] == nil && openAI["max_completion_tokens"] as? Int == 4000 && openAI["reasoning_effort"] as? String == "minimal")
        #expect(try body(.openAI, model: "gpt-4.1")["reasoning_effort"] == nil)
        #expect(try body(.gemini, model: "gemini-2.5-pro")["model"] as? String == "gemini-2.5-pro")
        #expect(CoachClient.explain(status: 401, body: Data(), provider: .gemini).contains("Gemini key in Settings"))
        #expect(CoachClient.explain(status: 404, body: Data(), provider: .openAI, model: "gpt-x").contains("OpenAIModel"))
        // Provider error bodies are untrusted and can echo credentials.
        #expect(CoachClient.explain(status: 400, body: Data(#"[{"error":{"message":"API key not valid"}}]"#.utf8), provider: .gemini).contains("Check the selected model"))
    }
}
