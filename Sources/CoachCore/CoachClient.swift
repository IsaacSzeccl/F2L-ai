import Foundation

/// A screen position suggested by the model, in thousandths of the screenshot, or a semantic Excel cell.
public struct ScreenTarget: Equatable, Sendable {
    public var left, top, right, bottom: Int
    public var label: String
    public var cell: String?

    public init(left: Int, top: Int, right: Int, bottom: Int, label: String, cell: String? = nil) {
        (self.left, self.top, self.right, self.bottom, self.label, self.cell) = (left, top, right, bottom, label, cell)
    }

    /// Whether the model gave where it is on the screenshot (a cell may come with or without one).
    public var hasBox: Bool { right > left && bottom > top }
}

public struct CoachAnswer: Sendable {
    public var reply: String
    public var steps: [String]
    /// Where each step happens on screen, when the model could see it (same length as `steps`).
    public var stepTargets: [ScreenTarget?]
    public var target: ScreenTarget?

    public init(reply: String, steps: [String] = [], stepTargets: [ScreenTarget?] = [], target: ScreenTarget?) {
        self.reply = reply
        self.steps = steps
        self.stepTargets = steps.indices.map { stepTargets.indices.contains($0) ? stepTargets[$0] : nil }
        self.target = target
    }

    /// What Pip shows, speaks and saves: the reply, then the steps numbered one per line.
    public var text: String {
        let reply = TeachingReply.clean(self.reply)
        guard !steps.isEmpty else { return reply }
        return reply + "\n\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}

public struct CoachRequestError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The teaching client: one prompt and one answer format, sent to whichever provider is chosen (DeepSeek, ChatGPT,
/// Gemini, GLM through the OpenAI chat format; Claude through the Messages API). Prompt, payload and wording match
/// Windows/F2L.Windows/CoachClient.cs.
public struct CoachClient: Sendable {
    public static let teachingPrompt = TeachingReply.style + "\n" + """
        You are F2L, a practical coach that helps people set up and use AI tools and everyday work apps on their own
        computer: AI assistants such as ChatGPT, Gemini, Claude, Grok, DeepSeek, Copilot and Tencent WorkBuddy, and work apps
        such as Notion, Google Workspace, Microsoft 365, Canva, Zoom and Excel. Use plain language and never patronize the learner.
        Teach the tool the learner asks about even when it is not on screen yet: start from where they are, for example opening
        the browser, going to the tool's official website or app store page, signing in, then the first useful feature. Never
        refuse or stop because a different app is in front; mention what the screenshot shows only when it helps the next step.
        When a screenshot is provided, use only what it visibly supports for places on screen. When the message carries a
        checked recipe, follow it: give every one of its steps in order, leave none out, and keep its on-screen names unless
        the screenshot shows a different name for the same control, in which case the screen wins on the name while the recipe
        still sets the order and what must not be left out. When it carries no recipe and you are unsure how a tool works
        today, say so in one short sentence and then either ask one short question or name the tool's official site; never
        invent a menu, a button or a menu path. If no screenshot is provided, say so naturally when screen details matter. You cannot
        control this computer or click buttons. Ask one short clarifying question only when the request genuinely needs more
        context. Return only a JSON
        object with exactly three keys: "reply", "steps" and "target". "reply" must be natural spoken language, without
        markdown, bullet lists, emojis, or URLs. When the task takes more than one action, "reply" is one short sentence
        saying what the steps achieve, and "steps" lists every action in order, one precise action per item, naming the
        exact keys for the learner's computer (Command on macOS, Ctrl on Windows), whether to hold them, and the exact cells,
        menus and buttons, for example ["Click A1.", "Hold Shift and click A4.", "Hold Command and drag from D1 to D4."].
        Otherwise "steps" is an empty list. Start from what the learner has already done: leave out steps that Excel
        reports as already selected. When the message says what Excel reports, trust it over the screenshot for which
        cells are selected. Do not mention easy or hard modes. "target" is null unless the screenshot
        clearly shows the place the learner should act on next: a button, tab, menu, icon, field or cell. Then it
        contains integer left, top, right and bottom coordinates from 0 to 1000 and a label that is the control's exact
        visible name or tooltip, written as the screen shows it, in the app's own language (新增 when the app shows 新增, not
        "Add"), such as "Insert" or "Recommended Charts", so the host can find it. Coordinates are
        thousandths of the screenshot and tightly surround the whole visible control. For an Excel cell or range, also
        add "cell" with its address, such as
        {"reply":"Select cell A1.","steps":[],"target":{"cell":"A1","label":"A1","left":120,"top":210,"right":180,"bottom":228}}.
        The host checks cells with Excel where it can. Each step can point at its own place: write that step as
        {"text":"Open the Insert tab.","target":{"left":300,"top":40,"right":350,"bottom":60,"label":"Insert"}} instead
        of a plain string. Give a target for every step whose place is visible, and for the reply whenever it tells the learner
        to act on something visible; never guess a place you cannot see.
        Positions read from a screenshot are approximate; never claim an exact verified match.
        Use short paragraphs with blank lines for longer explanations so the learner can follow the reply.
        """

    public var settings: @Sendable () -> CoachSettings
    public var session: URLSession

    /// Like Windows' HttpClient.Timeout, 45 seconds covers the whole request, not just the wait between packets.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration, delegate: ProviderSessionDelegate(), delegateQueue: nil)
    }()

    /// Settings are read for every question, so switching provider (Pip's menu or local.settings.json) applies at once.
    public init(settings: @escaping @Sendable () -> CoachSettings = CoachSettings.current, session: URLSession = CoachClient.defaultSession) {
        self.settings = settings
        self.session = session
    }

    /// A fixed provider and key, for tests and tools.
    public init(apiKey: @escaping @Sendable () -> String, provider: Provider = .deepSeek, model: String? = nil,
                session: URLSession = CoachClient.defaultSession) {
        self.init(settings: { CoachSettings(provider: provider, model: model, apiKey: apiKey()) }, session: session)
    }

    public var isConfigured: Bool { !settings().apiKey.isEmpty }
    public var provider: Provider { settings().provider }
    public var notConfigured: String { settings().provider.notConfigured() }

    /// `jsonMode` asks for a JSON object where the provider supports it; the retry after an empty reply leaves it off.
    public static func requestBody(question: String, history: [(role: String, content: String)], jpeg: Data?, jsonMode: Bool = true,
                                   provider: Provider = .deepSeek, model: String? = nil, systemPrompt: String = teachingPrompt,
                                   maxTokens: Int? = nil) throws -> Data {
        let model = (model?.isEmpty == false ? model! : provider.defaultModel)
        let past: [[String: Any]] = history.suffix(20).map { ["role": $0.role, "content": $0.role == "assistant" ? historyReply($0.content) : $0.content] }
        let image = jpeg.flatMap { $0.isEmpty ? nil : $0.base64EncodedString() }
        if provider == .claude {
            // Messages API: the system prompt is separate, and the picture goes before the question.
            var content: [[String: Any]] = []
            if let image { content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image]]) }
            content.append(["type": "text", "text": question])
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 4096,
                "system": systemPrompt,
                "messages": past + [["role": "user", "content": content]],
                "output_config": ["effort": "low"], // quick, short teaching replies
                "fallbacks": "default", // answered by another Claude model if this one declines
            ]
            return try JSONSerialization.data(withJSONObject: body)
        }
        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]] + past
        if let image {
            var picture: [String: Any] = ["url": "data:image/jpeg;base64,\(image)"]
            if provider == .deepSeek || provider == .openAI { picture["detail"] = "high" }
            messages.append(["role": "user", "content": [["type": "text", "text": question], ["type": "image_url", "image_url": picture]]])
        } else {
            messages.append(["role": "user", "content": question])
        }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        switch provider {
        case .deepSeek:
            body["thinking"] = ["type": "disabled"]
            body["temperature"] = 0.2
            body["max_tokens"] = maxTokens ?? 650 // short teaching replies; a starter plan asks for more
        case .openAI:
            // Reasoning models only take the default temperature and count their reasoning in this limit.
            body["max_completion_tokens"] = 4000
            if model.hasPrefix("gpt-5") || model.hasPrefix("o") { body["reasoning_effort"] = "minimal" }
        case .glm:
            body["thinking"] = ["type": "disabled"]
            body["temperature"] = 0.2
            body["max_tokens"] = 2000
        case .gemini, .claude:
            body["temperature"] = 0.2
            body["max_tokens"] = 4000
        }
        if jsonMode { body["response_format"] = ["type": "json_object"] }
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Earlier replies go back in the JSON shape the model answers in. With plain-text replies in the
    /// history, DeepSeek's JSON mode returns nothing but spaces ("I couldn't form a reply").
    public static func historyReply(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ["reply": text, "target": NSNull()], options: [.sortedKeys, .withoutEscapingSlashes])
        else { return text }
        return String(decoding: data, as: UTF8.self)
    }

    public func answer(question: String, history: [(role: String, content: String)], jpeg: Data?) async throws -> CoachAnswer {
        let current = settings()
        guard !current.apiKey.isEmpty else { throw CoachRequestError(current.provider.notConfigured()) }
        // JSON mode occasionally returns only whitespace. Ask once more without it before giving up.
        let first: CoachAnswer?
        do { first = try await send(current, question: question, history: history, jpeg: jpeg, jsonMode: true) }
        catch let error as CoachRequestError where error.message == current.provider.unreadable() { first = nil }
        if let first { return first }
        if let second = try await send(current, question: question, history: history, jpeg: jpeg, jsonMode: false) { return second }
        throw CoachRequestError(current.provider.noReply())
    }

    private func send(_ current: CoachSettings, question: String, history: [(role: String, content: String)], jpeg: Data?,
                      jsonMode: Bool) async throws -> CoachAnswer? {
        let data = try await response(current, question: question, history: history, jpeg: jpeg, jsonMode: jsonMode)
        return try Self.parse(responseBody: data, provider: current.provider)
    }

    /// Explicit, text-only setup request. No screenshot or conversation history is collected.
    public func starterPlan(for profile: LearnerProfile) async throws -> StarterPlan {
        let current = settings()
        guard !current.apiKey.isEmpty else { throw CoachRequestError(current.provider.notConfigured()) }
        let data = try await response(current, question: StarterPlan.question(for: profile), history: [], jpeg: nil,
                                      jsonMode: true, systemPrompt: StarterPlan.systemPrompt, maxTokens: 2000)
        guard let text = try Self.responseText(data, provider: current.provider) else { throw CoachRequestError(current.provider.noReply()) }
        return try StarterPlan.parse(text, provider: current.provider.name)
    }

    func response(_ current: CoachSettings, question: String, history: [(role: String, content: String)], jpeg: Data?,
                          jsonMode: Bool, systemPrompt: String = teachingPrompt, maxTokens: Int? = nil) async throws -> Data {
        let provider = current.provider
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .claude {
            request.setValue(current.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        } else {
            request.setValue("Bearer \(current.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try Self.requestBody(question: question, history: history, jpeg: jpeg, jsonMode: jsonMode,
                                                provider: provider, model: current.model, systemPrompt: systemPrompt, maxTokens: maxTokens)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw CoachRequestError(provider.tooSlow())
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet].contains(error.code) {
            throw CoachRequestError(provider.hostUnreachable())
        } catch {
            throw CoachRequestError(provider.connectionFailed())
        }
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CoachRequestError(Self.explain(status: status, body: data, provider: provider, model: current.model))
        }
        return data
    }

    /// Reads a reply. Returns nil when it is blank or has no "reply", so the caller can ask again.
    public static func parse(responseBody data: Data, provider: Provider = .deepSeek) throws -> CoachAnswer? {
        guard let text = try responseText(data, provider: provider) else { return nil }
        return try readReply(text, provider: provider)
    }

    static func responseText(_ data: Data, provider: Provider) throws -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoachRequestError(provider.unreadable()) }
        var text: String?
        if provider == .claude {
            // Messages API: content blocks; only the text blocks are the answer.
            if root["stop_reason"] as? String == "refusal" { throw CoachRequestError(provider.declined()) }
            guard let blocks = root["content"] as? [[String: Any]] else { throw CoachRequestError(provider.unreadable()) }
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        } else {
            guard let choices = root["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
                  message["content"] != nil else { throw CoachRequestError(provider.unreadable()) }
            if let string = message["content"] as? String { text = string }
            if let parts = message["content"] as? [Any] {
                text = parts.compactMap { ($0 as? [String: Any])?["text"] as? String }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static let fenceStart = try! NSRegularExpression(pattern: #"\A```[A-Za-z]*"#)
    static let fenceEnd = try! NSRegularExpression(pattern: #"```\s*\z"#)

    /// The model's message: a JSON object (optionally in a code fence), or plain text when JSON mode was off.
    static func readReply(_ text: String, provider: Provider = .deepSeek) throws -> CoachAnswer? {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = fenceStart.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
            clean = fenceEnd.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !clean.isEmpty else { return nil }
        guard clean.hasPrefix("{") else { return CoachAnswer(reply: TeachingReply.clean(clean), target: nil) }
        guard let answer = try? JSONSerialization.jsonObject(with: Data(clean.utf8)) as? [String: Any] else { throw CoachRequestError(provider.unreadable()) }
        guard let reply = (answer["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty else { return nil }
        let steps = parseSteps(answer["steps"])
        return CoachAnswer(reply: TeachingReply.clean(reply), steps: steps.map(\.text), stepTargets: steps.map(\.target),
                           target: parseTarget(answer["target"]))
    }

    /// Up to 12 non-empty steps. Each is a string, or {"text": ..., "target": ...} when the model can see where it happens.
    static func parseSteps(_ value: Any?) -> [(text: String, target: ScreenTarget?)] {
        guard let items = value as? [Any] else { return [] }
        let steps: [(text: String, target: ScreenTarget?)] = items.compactMap { item in
            let object = item as? [String: Any]
            guard let text = ((item as? String) ?? (object?["text"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return (text, parseTarget(object?["target"]))
        }
        return Array(steps.prefix(12))
    }

    /// The question as sent to the model: the learner's words, then which computer they use and, for desktop Excel,
    /// what Excel reports about the selection. Only the learner's words are saved in the conversation.
    public static func compose(question: String, platform: String, excel: ExcelContext?, profile: LearnerProfile? = nil,
                               app: String? = nil, windowTitle: String? = nil, screenNames: [String] = [],
                               library: AIToolLibrary? = nil, recipes: RecipeLibrary? = nil, account: String = "") -> String {
        var context = "Learner's computer: \(platform)."
        // Which app the screenshot shows, so a question about another tool is taught from there, not refused.
        if let app, !app.isEmpty { context += " The screenshot shows \(app)." }
        if let excel { context += " " + excel.promptLine }
        let found = reference(question: question, profile: profile, app: app, windowTitle: windowTitle,
                              library: library, recipes: recipes, account: account)
        return question + "\n\n(" + context + ")" + ScreenNames.line(screenNames) + found.notes + (profile?.coachingContext ?? "")
    }

    /// What one question resolves to: the tools, the recipes, and the reference text those two produce. `compose`
    /// builds the question from it, and the host uses the same recipes to check their on-screen names before pointing
    /// at them, so both see exactly the same selection.
    public static func reference(question: String, profile: LearnerProfile? = nil, app: String? = nil,
                                 windowTitle: String? = nil, library: AIToolLibrary? = nil,
                                 recipes: RecipeLibrary? = nil, account: String = "")
        -> (tools: [AITool], recipes: [Recipe], notes: String) {
        // The tool is resolved from the app in front before the question's own words, so a bare "Copilot" in Word is
        // not answered with GitHub Copilot's coding notes.
        let tools = library?.resolve(question: question, app: app, windowTitle: windowTitle) ?? []
        var notes = library?.referenceNotes(question: question, profile: profile, tools: tools) ?? ""
        var chosen: [Recipe] = []
        if let recipes, !tools.isEmpty {
            let moment = RecipeContext(question: question, app: app ?? "", windowTitle: windowTitle ?? "", account: account, profile: profile)
            chosen = recipes.select(moment, tools: tools)
            if !chosen.isEmpty { notes += recipes.notes(for: chosen) }
            // Only a how-to question is told there is no recipe; a greeting or a quick fact needs no such warning.
            else if QuestionIntent.classify(question) == .procedural { notes += RecipeLibrary.noRecipeNote }
        }
        return (tools, chosen, notes)
    }

    static func parseTarget(_ value: Any?) -> ScreenTarget? {
        guard let target = value as? [String: Any] else { return nil }
        if let cellText = target["cell"] as? String {
            // A range such as "A1:A4" is named by its first cell; the box (if any) covers the whole range.
            guard let cell = CellReference.parse(String(cellText.split(separator: ":").first ?? "")) else { return nil }
            var semantic = ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: cellText.uppercased().replacingOccurrences(of: "$", with: ""), cell: cell.address)
            if let box = parseTarget(target.filter { $0.key != "cell" }) {
                (semantic.left, semantic.top, semantic.right, semantic.bottom) = (box.left, box.top, box.right, box.bottom)
            }
            return semantic
        }
        // Whole JSON numbers only, as System.Text.Json's TryGetInt32 accepts: not 12.0, not true.
        func coordinate(_ key: String) -> Int? {
            guard let number = target[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), !CFNumberIsFloatType(number),
                  (0...1000).contains(number.intValue) else { return nil }
            return number.intValue
        }
        guard let left = coordinate("left"), let top = coordinate("top"), let right = coordinate("right"), let bottom = coordinate("bottom"),
              right > left, bottom > top, right - left <= 700, bottom - top <= 700 else { return nil }
        let label = (target["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ScreenTarget(left: left, top: top, right: right, bottom: bottom,
                            label: label.isEmpty ? "Next step" : String(label.prefix(36)), cell: nil)
    }

    static func explain(status: Int, body: Data, provider: Provider = .deepSeek, model: String? = nil) -> String {
        let name = provider.name, model = model ?? provider.defaultModel
        return switch status {
        case 401, 403: "\(name) rejected the configured API key (\(status)). Paste an active \(name) key in Settings (Pip’s ··· menu), then try again."
        case 402: "\(name) reports that the account has no available balance (402). Check the account's API balance, then try again."
        case 404: "\(name) couldn't find the requested model or endpoint (404). F2L is set to \(model); put a model your account can use in \(provider.modelProperty) in local.settings.json."
        case 429: "\(name) is rate-limiting requests (429). Wait a moment, then try again."
        case 503, 529: "\(name) is temporarily overloaded (\(status)). Wait a moment, then try again."
        case 400, 422: "\(name) rejected the request (\(status)). Check the selected model and request settings, then try again."
        default: "\(name) returned an error (\(status)). Check the local F2L status and try again."
        }
    }

}

/// Never forward credentials, questions, or screenshots to a redirected endpoint.
final class ProviderSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
