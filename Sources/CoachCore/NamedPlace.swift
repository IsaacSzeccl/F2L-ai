import Foundation

/// The AI sometimes names the place in words but leaves out where it is ("Click the Japan tile in the Recents row."
/// with no target). Then F2L still circles it: it takes the name the instruction points at and finds it on screen
/// itself (screen text and Accessibility), so the learner never has to ask "can you circle it?".
/// Mirrors Windows/F2L.Windows/NamedPlace.cs.
public enum NamedPlace {
    static let action = try! NSRegularExpression(
        pattern: #"\b(double-click|right-click|click|tap|select|choose|open|press|pick|go to|switch to|turn on|turn off|toggle|check|uncheck|find|type in|type into)\b"#,
        options: [.caseInsensitive])
    static let quoted = try! NSRegularExpression(pattern: #"["“'‘]([^"”'’\n]{1,40})["”'’]"#)
    /// Keyboard keys are pressed, not circled.
    static let keys: Set<String> = ["command", "cmd", "ctrl", "control", "shift", "option", "alt", "return", "enter", "escape", "esc",
                                    "space", "delete", "backspace", "fn", "windows", "win", "tab"]
    static let filler: Set<String> = ["the", "a", "an", "on", "your", "this", "that", "its", "it", "cell", "button", "tab", "menu", "icon"]

    /// The name of the thing an instruction tells the learner to act on, or nil when it names nothing on screen.
    public static func label(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let verb = action.firstMatch(in: text, range: range), let after = Range(verb.range, in: text) else { return nil }
        let rest = String(text[after.upperBound...])
        let restRange = NSRange(rest.startIndex..., in: rest)
        if let quote = quoted.firstMatch(in: rest, range: restRange), let inner = Range(quote.range(at: 1), in: rest) {
            let name = rest[inner].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        var run: [String] = []
        for (index, raw) in rest.split(whereSeparator: \.isWhitespace).enumerated() {
            let word = raw.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "+")))
            let ends = raw.last.map { ".,;:!?".contains($0) } ?? false
            let isKey = word.lowercased().split(separator: "+").contains { keys.contains(String($0)) }
            // "Gemini's table": the owner, not the control. 上傳檔案 has no capitals but is a name.
            let possessive = word.hasSuffix("'s") || word.hasSuffix("’s")
            let named = !isKey && !possessive && (word.first?.isUppercase == true || CellReference.parse(word) != nil || TargetSnap.isWideScript(word))
            if possessive && run.isEmpty { continue }
            if named { run.append(word) }
            else if !run.isEmpty || isKey || index >= 6 { break }
            else if !filler.contains(word.lowercased()) && index >= 3 { break }
            if ends || run.count == 4 { break }
        }
        let name = run.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    /// A place with no position: the host finds it on screen by its name (or checks it with Excel when it is a cell).
    public static func target(in text: String) -> ScreenTarget? {
        guard let label = label(in: text) else { return nil }
        // A cell ("A4") or a range ("A1:A4") is checked with Excel from its first cell, like the AI's own cell targets.
        let parts = label.split(separator: ":").map(String.init)
        let cell = parts.count <= 2 && parts.allSatisfy({ CellReference.parse($0) != nil }) ? CellReference.parse(parts[0])?.address : nil
        return ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: label, cell: cell)
    }
}

extension CoachAnswer {
    /// Where each lesson step points: its own place; else the reply's place when the step names it (or is the only
    /// step); else the thing the step names, found on screen by name.
    public var placesForSteps: [ScreenTarget?] {
        steps.indices.map { index in
            if let own = stepTargets[index] { return own }
            if let target, steps.count == 1 || Self.mentions(steps[index], target.label) { return target }
            return NamedPlace.target(in: steps[index])
        }
    }

    /// Where a plain reply points: the AI's place, or the thing the reply tells the learner to act on.
    public var placeForReply: ScreenTarget? { target ?? (steps.isEmpty ? NamedPlace.target(in: reply) : nil) }

    static func mentions(_ step: String, _ label: String) -> Bool {
        let name = TargetSnap.normalise(label)
        return !TargetSnap.generic.contains(name) && TargetSnap.normalise(step).contains(name)
    }
}
