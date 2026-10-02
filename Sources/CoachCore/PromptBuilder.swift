import Foundation

public enum PromptBuilder {
    public static let maxElements = 150
    public static let maxLabelLength = 70
    public static let maxHistoryMessages = 10

    public static let systemPrompt = """
    You are Beacon, a warm, patient voice coach sitting beside someone who is learning to use AI tools \
    such as ChatGPT, Gemini and Copilot. Many learners are returning to work after years away. They are \
    capable adults who talk comfortably but feel unsure with unfamiliar screens.

    You can see their front window: a list of ON-SCREEN CONTROLS read from the computer, and often a \
    screenshot. You can circle things on their screen with tools. You never click or type for them: you \
    point, they act.

    How to speak:
    - Your words are read aloud. Use plain spoken English. No markdown, no bullet points, no emoji, no URLs.
    - Keep each reply to one to three short sentences. Give ONE step at a time, then wait.
    - Avoid jargon. If a technical word is unavoidable, explain it in a few words.
    - Be encouraging and specific ("Nice, that question is clear"), never patronising.

    How to point:
    - Whenever you ask them to click, type into, or look at a control, call point_at with its id from \
    the ON-SCREEN CONTROLS list, and refer to it by what it looks like ("the box that says Ask anything").
    - Always say at least one short sentence in the same reply as a tool call. A circle with no words \
    leaves the learner in silence.
    - Only use ids that appear in the current list. Never invent an id.
    - If the control you need is visible in the screenshot but missing from the list, use point_at_region \
    and say it is roughly there.
    - If you cannot see what they need at all, say so honestly and tell them how to get there (for example \
    scroll down, or open the website). Never guess about buttons you cannot see.
    - Call clear_pointer when the circle is no longer useful.

    Messages that start with [Screen event] are things the computer noticed (for example they finished \
    typing, or clicked the control you circled). React briefly and give the next single step, or say \
    nothing more than a short acknowledgement if no step is needed.
    """

    private static let roleNames: [String: String] = [
        "AXButton": "button", "AXTextField": "text box", "AXTextArea": "text box",
        "AXSearchField": "search box", "AXComboBox": "dropdown box", "AXPopUpButton": "dropdown",
        "AXMenuButton": "menu button", "AXMenuItem": "menu item", "AXMenuBarItem": "menu",
        "AXLink": "link", "AXCheckBox": "checkbox", "AXRadioButton": "option",
        "AXTab": "tab", "AXRadioGroup": "tab group", "AXSlider": "slider", "AXCell": "cell",
        "AXDisclosureTriangle": "expand arrow", "AXStaticText": "text", "AXImage": "image",
    ]

    public static func humanRole(_ axRole: String) -> String {
        roleNames[axRole] ?? axRole.replacingOccurrences(of: "AX", with: "").lowercased()
    }

    public static func describe(_ context: ScreenContext) -> String {
        var lines = ["SCREEN (front window)", "App: \(context.appName)"]
        if !context.windowTitle.isEmpty { lines.append("Window: \(context.windowTitle)") }
        if let summary = context.summary, !summary.isEmpty { lines.append("What is on screen: \(summary)") }
        if context.elements.isEmpty {
            lines.append("ON-SCREEN CONTROLS: none could be read from this window. Rely on the screenshot.")
        } else {
            lines.append("ON-SCREEN CONTROLS (id | type | label):")
            for element in context.elements.prefix(maxElements) {
                let label = String(element.label.prefix(maxLabelLength)).replacingOccurrences(of: "\n", with: " ")
                lines.append("\(element.id) | \(humanRole(element.role)) | \(label)")
            }
            if context.elements.count > maxElements {
                lines.append("(\(context.elements.count - maxElements) more controls not listed)")
            }
        }
        if context.screenshot != nil { lines.append("A screenshot of this window is attached.") }
        return lines.joined(separator: "\n")
    }

    /// Builds the full message list for one turn. Screen context rides on the newest user message only,
    /// so stale element ids never sit in the history as if they were current.
    public static func messages(
        history: [ChatMessage],
        context: ScreenContext,
        learnerText: String,
        attachScreenshot: Bool
    ) -> [ChatMessage] {
        var result = [ChatMessage(role: .system, text: systemPrompt)]
        result += history.suffix(maxHistoryMessages).map { ChatMessage(role: $0.role, text: $0.text) }
        let text = describe(context) + "\n\n" + learnerText
        let image = attachScreenshot ? context.screenshot : nil
        result.append(ChatMessage(role: .user, text: text, image: image))
        return result
    }

    public static func learnerUtterance(_ transcript: String) -> String {
        "Learner said: \"\(transcript)\""
    }

    public static func screenEvent(_ description: String) -> String {
        "[Screen event] \(description)"
    }

    public static let summaryPrompt = """
    In one short sentence, say which app or website this is and what the person seems to be doing \
    (for example: "ChatGPT home page with an empty message box"). No preamble.
    """
}

public enum ScreenReference {
    private static let cues = [
        "this", "that", "here", "there", "where", "screen", "see", "click", "button", "box", "page",
        "icon", "menu", "type", "press", "tap", "find", "show", "look", "what is", "what's", "how do",
        "next", "stuck", "now", "done", "open", "window",
    ]

    /// Whether a learner's words probably refer to what's on screen, so a fresh screenshot is worth
    /// its latency. Conservative: when in doubt, say yes.
    public static func needsFreshFrame(_ utterance: String) -> Bool {
        let text = " " + utterance.lowercased() + " "
        let padded = text.map { $0.isLetter || $0 == "'" ? String($0) : " " }.joined()
        return cues.contains { padded.contains(" \($0) ") } || utterance.split(separator: " ").count <= 3
    }
}
