import Foundation

/// What a step asks the learner to get to, when F2L can see it happen without a click on a circle: an app in front
/// ("Open your browser", "Open Excel") or a website open in the browser ("Go to chatgpt.com"). The host checks the app
/// in front and its window title a couple of times a second; Done stays for everything else.
/// Mirrors Windows/F2L.Windows/StepGoal.cs.
public enum StepGoal: Equatable, Sendable {
    /// Any web browser in front.
    case browser
    /// An app in front whose name contains one of these (lowercased).
    case app([String])
    /// A site open in the browser: the window title or address contains one of these (lowercased).
    case site([String])

    /// Browsers by their app name, Mac and Windows.
    public static let browsers = ["safari", "chrome", "edge", "firefox", "arc", "brave", "opera", "chromium", "vivaldi", "duckduckgo"]

    static let domain = try! NSRegularExpression(
        pattern: #"\b((?:[a-z0-9-]+\.)+(?:com|ai|so|app|dev|io|org|net|co|google|cn|me|new|chat))\b"#, options: [.caseInsensitive])
    static let opening = try! NSRegularExpression(
        pattern: #"\b(?i:open|launch|start|switch to|go to|bring up)\s+(?i:up\s+)?(?i:your\s+|the\s+|a\s+)?([A-Z][\w.+-]*(?:\s+[A-Z0-9][\w.+-]*){0,2})"#)
    static let browserWords = try! NSRegularExpression(pattern: #"\b(?:open|launch|start|switch to|use)\b[^.]*\b(?:browser|web browser)\b"#,
                                                       options: [.caseInsensitive])

    /// The goal a step names, or nil when only the learner can say it is done.
    public static func of(_ step: String, library: AIToolLibrary? = nil) -> StepGoal? {
        let range = NSRange(step.startIndex..., in: step)
        // A website first: "Go to chatgpt.com and sign in" is done once the page is open.
        if let match = domain.firstMatch(in: step, range: range), let found = Range(match.range(at: 1), in: step) {
            let host = step[found].lowercased().replacingOccurrences(of: "www.", with: "")
            var names = [host, String(host.split(separator: ".").first ?? "")]
            // The page title usually shows the tool's name ("Google Gemini", "Gemini Notebook").
            if let tool = library?.tools.first(where: { URL(string: $0.url)?.host?.replacingOccurrences(of: "www.", with: "") == host }) {
                names.append(tool.name.components(separatedBy: " (")[0].lowercased())
            }
            return .site(names.filter { $0.count >= 2 })
        }
        if browserWords.firstMatch(in: step, range: range) != nil { return .browser }
        if let match = opening.firstMatch(in: step, range: range), let found = Range(match.range(at: 1), in: step) {
            let name = step[found].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if browsers.contains(where: name.contains) { return .browser }
            // "Open the Insert tab" names a place inside the app, not an app.
            let places = ["tab", "menu", "page", "panel", "dialog", "window", "settings", "sidebar", "file", "folder", "list", "box"]
            if !places.contains(where: { step.lowercased().contains("\(name) \($0)") }), name.count >= 3 { return .app([name]) }
        }
        return nil
    }

    /// Whether the app in front (and its window title) shows the goal reached.
    public func isMet(app: String, title: String) -> Bool {
        let app = app.lowercased(), title = title.lowercased()
        let inBrowser = Self.browsers.contains(where: app.contains)
        switch self {
        case .browser: return inBrowser
        case .app(let names): return names.contains { app.contains($0) || $0.contains(app) && app.count >= 3 }
        case .site(let names): return inBrowser && names.contains(where: title.contains)
        }
    }
}
