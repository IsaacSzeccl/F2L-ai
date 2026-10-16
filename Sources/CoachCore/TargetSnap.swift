import CoreGraphics
import Foundation

/// A real control another app reports through Accessibility (Mac) or UI Automation (Windows): its frame in global
/// top-left coordinates and its accessible name.
public struct ControlCandidate: Equatable, Sendable {
    public var frame: CGRect
    public var name: String
    public init(frame: CGRect, name: String) {
        self.frame = frame
        self.name = name
    }
}

/// Turns the model's rough place on a screenshot into the real control, so Pip points at the actual button, tab or
/// menu and not a few pixels off. Mirrors Windows/F2L.Windows/TargetSnap.cs.
public enum TargetSnap {
    /// Labels that say nothing about which control is meant.
    static let generic: Set<String> = ["", "next step", "here", "this", "button", "target", "cell"]
    /// Whether a label names nothing in particular ("Next step", "here").
    public static func isGeneric(_ label: String) -> Bool { generic.contains(normalise(label)) }

    /// "Insert tab" → "insert"; "Pie Chart button…" → "pie chart".
    public static func normalise(_ text: String) -> String {
        var words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, words.count > 1, ["tab", "button", "menu", "icon", "option", "command", "control"].contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    public static func matches(_ name: String, _ label: String) -> Bool {
        let name = normalise(name)
        guard !name.isEmpty else { return false }
        if name == label { return true }
        // Every meaningful word of one is in the other: "pie chart" matches "Insert Pie or Doughnut Chart",
        // "insert" matches "Insert". Short words ("or", "a") don't count.
        // Chinese and Japanese have no spaces and short words (新增, 設定): one inside the other counts.
        if isWideScript(label) || isWideScript(name), min(name.count, label.count) >= 2 {
            // Spaces mean little between Chinese words. A fragment of a long label (記錄 inside 為技能命名，例如「會議記錄
            // 摘要工具」, or Gemini inside 問問 Gemini) is not the control.
            let name = name.replacingOccurrences(of: " ", with: ""), label = label.replacingOccurrences(of: " ", with: "")
            return name.contains(label) || (label.contains(name) && name.count * 4 > label.count * 3)
        }
        func words(_ text: String) -> Set<String> { Set(text.split(separator: " ").map(String.init).filter { $0.count >= 3 }) }
        let nameWords = words(name), labelWords = words(label)
        guard !nameWords.isEmpty, !labelWords.isEmpty else { return false }
        // A shorter name must still cover most of the label: "Gemini" alone is not "Customize Gemini".
        return labelWords.isSubset(of: nameWords) || (nameWords.isSubset(of: labelWords) && nameWords.count * 3 >= labelWords.count * 2)
    }

    /// Switch-like controls rename themselves: the sidebar button says "Close sidebar" once the sidebar is open.
    static let opposites: [(String, String)] = [("open", "close"), ("show", "hide"), ("expand", "collapse"), ("turn on", "turn off"),
                                                 ("enable", "disable"), ("unmute", "mute"), ("start", "stop"), ("maximize", "restore"),
                                                 ("開啟", "關閉"), ("打開", "關閉"), ("打开", "关闭"), ("展開", "收合"), ("展开", "收起"),
                                                 ("顯示", "隱藏"), ("显示", "隐藏"), ("開く", "閉じる"), ("表示", "非表示")]

    /// Whether a control named `name` shows the step `label` has already happened: "Open Sidebar" against
    /// "Close sidebar", "Unmute" against "Mute", 開啟側邊欄 against 關閉側邊欄.
    public static func alreadyDone(label: String, name: String) -> Bool {
        let label = normalise(label), name = normalise(name)
        for (on, off) in opposites where label.hasPrefix(on) && name.hasPrefix(off) {
            let wanted = label.dropFirst(on.count).trimmingCharacters(in: .whitespaces)
            let shown = name.dropFirst(off.count).trimmingCharacters(in: .whitespaces)
            // "unmute" starts with "un", never with "mute": the prefix check above keeps them apart.
            if wanted == shown || (!wanted.isEmpty && !shown.isEmpty && matches(shown, wanted)) { return true }
        }
        return false
    }

    /// Han, kana or hangul in the text.
    static func isWideScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value)
            || (0xAC00...0xD7AF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
    }

    public static func sensible(_ frame: CGRect) -> Bool {
        frame.width >= 6 && frame.height >= 6 && frame.width <= 700 && frame.height <= 300
    }

    /// The control the model meant, or nil to keep its own (approximate) box.
    /// - A control whose name matches the label wins, nearest to the model's box when there is one.
    /// - Otherwise the smallest control under the middle of the box, if it is about the box's size.
    /// Words read off the screen are only matched by name (`byPosition: false`): a stray "2" under the model's spot
    /// is not the Fill button.
    public static func snap(box: CGRect?, label: String, candidates: [ControlCandidate], byPosition: Bool = true) -> CGRect? {
        let label = normalise(label)
        let usable = candidates.filter { sensible($0.frame) }
        func distance(_ frame: CGRect) -> CGFloat {
            guard let box else { return 0 }
            return hypot(frame.midX - box.midX, frame.midY - box.midY)
        }
        if !generic.contains(label) {
            let named = usable.filter { matches($0.name, label) }
            // Exact names beat partial ones; then the nearest to where the model looked.
            let exact = named.filter { normalise($0.name) == label }
            let pool = exact.isEmpty ? named : exact
            // The model's position is often far off, so a named control wins wherever it is; the box only breaks ties.
            if box != nil, let best = pool.min(by: { distance($0.frame) < distance($1.frame) }) {
                return best.frame
            } else if pool.count == 1 {
                return pool[0].frame
            }
        }
        guard byPosition, let box else { return nil }
        let center = CGPoint(x: box.midX, y: box.midY)
        let area = max(1, box.width * box.height)
        return usable.filter { $0.frame.containsIncludingEdges(center) }
            .filter { ($0.frame.width * $0.frame.height) / area >= 0.2 && ($0.frame.width * $0.frame.height) / area <= 5 }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.frame
    }

    /// The ellipse Pip circles a target with: it passes just outside the target's corners, so a short cell or a long
    /// range is fully inside without covering much of its neighbours.
    public static func circle(around target: CGRect, margin: CGFloat = 5) -> CGRect {
        let a = target.width / 2 * 2.squareRoot() + margin
        let b = target.height / 2 * 2.squareRoot() + margin
        return CGRect(x: target.midX - a, y: target.midY - b, width: a * 2, height: b * 2)
    }
}

/// What Excel for Mac reports about a cell, in points of the sheet: Excel for Mac gives no screen positions, so the
/// cell is placed from these and the worksheet grid's Accessibility frame.
public struct ExcelCellMetrics: Equatable, Sendable {
    public var visibleLeft, visibleTop, left, top, width, height, zoom: Double
    public var headings: Bool
    public init(visibleLeft: Double, visibleTop: Double, left: Double, top: Double, width: Double, height: Double, zoom: Double, headings: Bool) {
        (self.visibleLeft, self.visibleTop, self.left, self.top, self.width, self.height, self.zoom, self.headings) =
            (visibleLeft, visibleTop, left, top, width, height, zoom, headings)
    }
}

public enum ExcelGeometry {
    /// Where the cell would be for each way Excel may draw its grid: headings inside the grid's frame or not, and
    /// 72 or 96 dots per inch at 100% zoom. Only cells whose middle is inside the grid are kept.
    public static func candidates(_ m: ExcelCellMetrics, grid: CGRect) -> [CGRect] {
        guard m.zoom > 0, m.width > 0, m.height > 0, grid.width > 0, grid.height > 0 else { return [] }
        var rects: [CGRect] = []
        for dpi in [1.0, 4.0 / 3.0] {
            let z = CGFloat(m.zoom / 100 * dpi)
            let offsets: [CGPoint] = m.headings ? [.zero, CGPoint(x: 30 * z, y: 18 * z)] : [.zero]
            for offset in offsets {
                let rect = CGRect(x: grid.minX + offset.x + CGFloat(m.left - m.visibleLeft) * z,
                                  y: grid.minY + offset.y + CGFloat(m.top - m.visibleTop) * z,
                                  width: CGFloat(m.width) * z, height: CGFloat(m.height) * z)
                if grid.containsIncludingEdges(CGPoint(x: rect.midX, y: rect.midY)) { rects.append(rect) }
            }
        }
        return rects
    }

    /// The candidate that agrees with where the model saw the cell on the screenshot. Without that, only a single
    /// possible placement is trusted.
    public static func choose(_ candidates: [CGRect], near box: CGRect?) -> CGRect? {
        guard let box else { return candidates.count == 1 ? candidates[0] : nil }
        func distance(_ r: CGRect) -> CGFloat { hypot(r.midX - box.midX, r.midY - box.midY) }
        guard let best = candidates.min(by: { distance($0) < distance($1) }) else { return nil }
        return distance(best) <= max(48, box.height * 2.5, best.height * 2.5) ? best : nil
    }
}
