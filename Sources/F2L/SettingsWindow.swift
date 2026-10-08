import AppKit
import CoachCore

/// Mirrors SettingsWindow.xaml: which AI is used, where keys live, and what is stored.
enum SettingsWindow {
    @MainActor
    static func make() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 452, height: 440), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "F2L Settings"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.panel
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 452, height: 440))
        window.contentView = root
        let file = LocalSettings.settingsFile()?.path ?? LocalSettings.userFile.path
        let shortFile = file.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let muted = Palette.hex(0x737780), accent = Palette.lavenderInk
        var y: CGFloat = 28
        func add(_ view: NSTextField, gap: CGFloat, width: CGFloat = 396) {
            y += gap
            let height = view.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 400)).height ?? 18
            view.frame = NSRect(x: 28, y: y, width: width, height: ceil(height))
            root.addSubview(view)
            y = view.frame.maxY
        }
        add(makeLabel("F2L settings", size: 23, weight: .semibold, color: Palette.ink), gap: 0)
        add(makeLabel("AI coach", size: 14, weight: .semibold, color: Palette.ink), gap: 19)
        let current = CoachSettings.current()
        add(makeLabel("\(current.provider.name) · \(current.model)\(current.apiKey.isEmpty ? " · no key yet" : "")", size: 14, color: accent), gap: 4)
        add(makeLabel("Switch with AI provider in Pip's menu, or set \"Provider\" in the file below (deepseek, openai, gemini, claude, glm).",
                      size: 12, color: muted, wraps: true), gap: 4)
        add(makeLabel("F2L reads the active app window when you send a question, unless screen sharing is paused from Pip's menu.",
                      size: 14, color: muted, wraps: true), gap: 7)
        add(makeLabel("Your local configuration", size: 14, weight: .semibold, color: Palette.ink), gap: 16)
        let path = makeLabel(shortFile, size: 14, color: accent)
        path.isSelectable = true
        path.lineBreakMode = .byTruncatingMiddle
        add(path, gap: 4)
        add(makeLabel("Keys stay in this private file on this computer. Git ignores it, and scripts/check-secrets.sh stops a commit that contains a key.",
                      size: 14, color: muted, wraps: true), gap: 7)
        let note = makeLabel("The latest 500 messages and your draft are saved on this device. Screenshots aren't saved. Simple cell-pointing requests stay on this Mac; other questions and their shared screen image go to the AI provider you chose.",
                             size: 11, color: muted, wraps: true)
        let box = RoundedBox(fill: Palette.hex(0xF3F1F8), radius: 12)
        let noteHeight = ceil(note.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 372, height: 400)).height ?? 40)
        box.frame = NSRect(x: 28, y: y + 14, width: 396, height: noteHeight + 24)
        note.frame = NSRect(x: 12, y: 12, width: 372, height: noteHeight)
        box.addSubview(note)
        root.addSubview(box)
        let reveal = FlatButton("Show file", size: 12)
        reveal.padding = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        // Creates an empty file to fill in when there isn't one yet, then shows it in Finder.
        reveal.onClick = { NSWorkspace.shared.activateFileViewerSelecting([LocalSettings.prepareFile()]) }
        let done = FlatButton("Done", size: 12)
        done.padding = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        done.onClick = { [weak window] in window?.close() }
        let doneSize = done.intrinsicContentSize, revealSize = reveal.intrinsicContentSize
        done.frame = NSRect(x: 424 - doneSize.width, y: 440 - 28 - 32, width: doneSize.width, height: 32)
        reveal.frame = NSRect(x: done.frame.minX - 8 - revealSize.width, y: done.frame.minY, width: revealSize.width, height: 32)
        root.addSubview(reveal)
        root.addSubview(done)
        return window
    }
}
