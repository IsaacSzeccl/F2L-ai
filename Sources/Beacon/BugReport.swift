import AppKit
import CoachCore
import Darwin
import OSLog
import SwiftUI

// MARK: - What gets captured

/// Everything about the most recent turn that is useful when something went wrong.
struct TurnDebug {
    var startedAt = Date()
    /// What triggered the turn: the learner's words, a typed question, or a screen event.
    var trigger = ""
    var provider = ""
    var model = ""
    var appName = ""
    var windowTitle = ""
    var windowFrame = CGRect.zero
    var summary: String?
    var elements: [ScreenElement] = []
    /// Exactly the screen text the model was given.
    var promptContext = ""
    var screenshot: ImageAttachment?
    var spoken = ""
    /// One line per tool call: what the model asked for and what the app did with it.
    var toolCalls: [String] = []
    var error: String?
}

struct BugSnapshot {
    var takenAt = Date()
    var phase = ""
    var status = ""
    var heard = ""
    var reply = ""
    var paused = false
    var history: [ChatMessage] = []
    var lastActions: [String] = []
    var turn: TurnDebug?
    var latency = ""
    var speech = SpeechStats()
    var circle: Annotation?
    var permissions: [String: Bool] = [:]
}

// MARK: - Where reports go

enum ProjectPaths {
    /// The project folder: the nearest parent of the app bundle that holds Package.swift.
    static func projectRoot() -> URL? {
        var current = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) { return current }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return nil
    }

    /// `<project>/bug-reports`, or a folder in Application Support if the app was moved out of the project.
    static func bugReportsFolder() -> URL {
        if let root = projectRoot() { return root.appendingPathComponent("bug-reports", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Beacon/bug-reports", isDirectory: true)
    }
}

// MARK: - Writing the report

struct BugReportsDisabled: LocalizedError {
    var errorDescription: String? { "Bug reports are turned off (BEACON_BUG_REPORTS=off)." }
}

@MainActor
enum BugReportWriter {
    @discardableResult
    static func write(_ snapshot: BugSnapshot, note: String, includeScreenshot: Bool) throws -> URL {
        guard BugReports.isEnabled else { throw BugReportsDisabled() }
        let root = ProjectPaths.bugReportsFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ensureReadme(in: root)

        let stamp = DateFormatter.folderStamp.string(from: snapshot.takenAt)
        let folder = root.appendingPathComponent("\(stamp)\(slug(note))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var screenshotName: String?
        if includeScreenshot, let image = snapshot.turn?.screenshot, let data = Data(base64Encoded: image.jpegBase64) {
            try data.write(to: folder.appendingPathComponent("screenshot.jpg"))
            screenshotName = "screenshot.jpg"
        }
        if let elements = snapshot.turn?.elements, !elements.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(elements).write(to: folder.appendingPathComponent("elements.json"))
        }
        let logs = recentLogs()
        try logs.write(to: folder.appendingPathComponent("logs.txt"), atomically: true, encoding: .utf8)
        try markdown(snapshot, note: note, screenshot: screenshotName, logLines: logs.split(separator: "\n").count)
            .write(to: folder.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        Log.app.notice("Bug report saved: \(folder.lastPathComponent, privacy: .public)")
        return folder
    }

    // MARK: Markdown

    private static func markdown(_ s: BugSnapshot, note: String, screenshot: String?, logLines: Int) -> String {
        var out: [String] = []
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        out.append("# Bug report \(DateFormatter.readable.string(from: s.takenAt))")
        out.append("")
        out.append("## What the tester says went wrong")
        out.append(trimmedNote.isEmpty ? "_(no note written)_" : trimmedNote)
        out.append("")
        out.append("## What was on the bar when the report was made")
        out.append("- Phase: \(s.phase)")
        out.append("- Status text: \(s.status.isEmpty ? "(empty)" : s.status)")
        out.append("- Last thing heard or typed: \(quote(s.heard))")
        out.append("- Reply on the bar: \(quote(s.reply))")
        out.append("- Paused: \(s.paused)")
        out.append("- Circle currently drawn: \(describe(s.circle))")
        out.append("")

        if let t = s.turn {
            out.append("## Last turn")
            out.append("- Started: \(DateFormatter.readable.string(from: t.startedAt))")
            out.append("- Trigger sent to the model: \(quote(t.trigger))")
            out.append("- Model: \(t.provider) / \(t.model)")
            out.append("- Front app: \(t.appName) – \"\(t.windowTitle)\"")
            out.append("- Window frame (top-left origin): \(rect(t.windowFrame))")
            out.append("- Controls read from the screen: \(t.elements.count)\(t.elements.isEmpty ? " (none: Accessibility returned nothing)" : "")")
            out.append("- Screen summary: \(t.summary ?? "(none)")")
            out.append("- Screenshot: \(screenshot.map { "`\($0)`" } ?? (t.screenshot == nil ? "none was taken for this turn" : "not included"))")
            out.append("- Latency: \(s.latency.isEmpty ? "(not measured)" : s.latency)")
            if let error = t.error { out.append("- **Error:** \(error)") }
            out.append("")
            out.append("### What the coach said")
            out.append(t.spoken.isEmpty ? "_(nothing)_" : t.spoken)
            out.append("")
            out.append("### Tool calls and what the app did")
            if t.toolCalls.isEmpty {
                out.append("_(the model called no tools)_")
            } else {
                t.toolCalls.forEach { out.append("- \($0)") }
            }
            out.append("")
            out.append("### Screen text the model was given")
            out.append("```")
            out.append(t.promptContext)
            out.append("```")
            out.append("")
        } else {
            out.append("## Last turn")
            out.append("_No question has been asked yet in this session._")
            out.append("")
        }

        out.append("## Conversation (most recent last)")
        if s.history.isEmpty {
            out.append("_(empty)_")
        } else {
            for message in s.history.suffix(12) { out.append("- **\(message.role.rawValue):** \(message.text.replacingOccurrences(of: "\n", with: " "))") }
        }
        if !s.lastActions.isEmpty { out.append("- _On screen after the last reply:_ \(s.lastActions.joined(separator: "; "))") }
        out.append("")

        out.append("## Speech recognition (last recording)")
        let sp = s.speech
        if sp.seconds == 0, sp.inputName == "?" {
            out.append("_No voice recording happened in this session (typed questions only, or none yet)._")
        } else {
        out.append("- Microphone: \(sp.inputName) · language \(sp.locale) · \(sp.onDevice ? "on this Mac" : "Apple servers")")
        out.append("- Loudest sound: \(Int(sp.peakDB)) dBFS · length \(String(format: "%.1f", sp.seconds)) s · partial results \(sp.partials)")
        out.append("- Final text: \(quote(sp.finalText))")
        out.append("- Recognizer error: \(sp.errorText ?? "none")")
        out.append("- Diagnosis: \(sp.diagnosis ?? "none")")
        }
        out.append("")

        out.append("## Settings (no secrets)")
        out.append(contentsOf: settingsLines())
        out.append("")
        out.append("## Permissions")
        for (name, granted) in s.permissions.sorted(by: { $0.key < $1.key }) { out.append("- \(name): \(granted ? "granted" : "**NOT granted**")") }
        out.append("")
        out.append("## Environment")
        out.append(contentsOf: environmentLines())
        out.append("")
        out.append("## Files in this folder")
        out.append("- `logs.txt`: Beacon's own log lines from the last 10 minutes (\(logLines) lines)")
        if s.turn?.elements.isEmpty == false { out.append("- `elements.json`: every control read from the screen, with ids, roles, labels and frames") }
        if let screenshot { out.append("- `\(screenshot)`: the exact picture sent to the model for the last turn") }
        return out.joined(separator: "\n") + "\n"
    }

    private static func settingsLines() -> [String] {
        [
            "- AI provider / coach model: \(Preferences.provider.rawValue) / \(Preferences.model)",
            "- Screen-summary model: \(Preferences.summaryModel) (background summaries \(Preferences.summaryLoopEnabled ? "on" : "off"))",
            "- Voice: ElevenLabs \(Preferences.ttsModel), voice id \(Preferences.voiceID)",
            "- Speech language: \(Preferences.speechLocale) · keep voice on this Mac: \(Preferences.speechOnDeviceOnly)",
            "- Chosen microphone: \(Preferences.inputDeviceUID ?? "system default")",
            "- API keys present: z.ai \(Secrets.has(.zai)), ElevenLabs \(Secrets.has(.elevenLabs)), Anthropic \(Secrets.has(.anthropic))",
        ]
    }

    private static func environmentLines() -> [String] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        return [
            "- Beacon \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(hardwareModel())",
            "- Screens: \(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height)) @\(Int($0.backingScaleFactor))x" }.joined(separator: ", "))",
            "- Signed with: \(signingNote())",
        ]
    }

    private static func signingNote() -> String {
        // Ad-hoc builds lose their permissions on every rebuild; worth knowing when permissions look wrong.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", Bundle.main.bundlePath]
        let pipe = Pipe()
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if text.contains("adhoc") { return "ad-hoc (permissions reset on every rebuild)" }
        return text.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier") }.map(String.init) ?? "unknown"
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    // MARK: Logs

    /// Beacon's own log lines from the last 10 minutes.
    private static func recentLogs(minutes: Double = 10, limit: Int = 300) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return "(system log unavailable)\n" }
        let start = store.position(date: Date().addingTimeInterval(-minutes * 60))
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
        guard let entries = try? store.getEntries(at: start, matching: predicate) else { return "(could not read system log)\n" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)"
        }
        return (lines.isEmpty ? "(no log lines in the last \(Int(minutes)) minutes)" : lines.suffix(limit).joined(separator: "\n")) + "\n"
    }

    // MARK: Helpers

    private static func quote(_ text: String) -> String {
        text.isEmpty ? "_(nothing)_" : "\"\(text.replacingOccurrences(of: "\n", with: " "))\""
    }

    private static func rect(_ r: CGRect) -> String {
        "x \(Int(r.minX)), y \(Int(r.minY)), \(Int(r.width))×\(Int(r.height))"
    }

    private static func describe(_ a: Annotation?) -> String {
        guard let a else { return "none" }
        return "\(a.style.rawValue) at \(rect(a.rect))\(a.caption.map { ", caption \"\($0)\"" } ?? "")\(a.elementID.map { ", element \($0)" } ?? "")"
    }

    private static func slug(_ note: String) -> String {
        let words = note.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(5)
        guard !words.isEmpty else { return "" }
        return "-" + words.joined(separator: "-")
    }

    private static func ensureReadme(in root: URL) throws {
        let url = root.appendingPathComponent("README.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try """
        # Bug reports

        Each folder is one report made with the **Report bug** button in Beacon. Newest folder = latest timestamp.

        - `report.md`: start here. The tester's note, what was on the bar, the last turn (what the model was shown, what it said, which tools it called and what the app did), the conversation, speech details, settings and permissions.
        - `screenshot.jpg`: the exact picture sent to the model.
        - `elements.json`: every control read from the screen (id, role, label, frame).
        - `logs.txt`: Beacon's log lines from the last 10 minutes.

        These contain screen content and typed text. They are git-ignored; do not share them publicly.

        To investigate: ask Claude to "read the latest bug report in bug-reports/ and fix it".
        """.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension DateFormatter {
    static let folderStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    static let readable: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

// MARK: - The window

@MainActor
final class BugReportController {
    private var window: NSWindow?

    func present(_ snapshot: BugSnapshot) {
        guard BugReports.isEnabled else { return }
        window?.close()
        let model = BugReportModel(snapshot: snapshot)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Report a bug"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BugReportView(model: model, onDone: { [weak self] in self?.window?.close() }))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
final class BugReportModel: ObservableObject {
    let snapshot: BugSnapshot
    @Published var note = ""
    @Published var includeScreenshot = true
    @Published var savedFolder: URL?
    @Published var errorText: String?

    init(snapshot: BugSnapshot) { self.snapshot = snapshot }

    var hasScreenshot: Bool { snapshot.turn?.screenshot != nil }

    func save() {
        do {
            savedFolder = try BugReportWriter.write(snapshot, note: note, includeScreenshot: includeScreenshot && hasScreenshot)
            errorText = nil
        } catch {
            errorText = "Could not save: \(error.localizedDescription)"
        }
    }
}

private struct BugReportView: View {
    @ObservedObject var model: BugReportModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let folder = model.savedFolder {
                saved(folder)
            } else {
                form
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What went wrong?").font(.headline)
            Text("Say what you did, what you expected, and what happened instead. Beacon adds the rest: the last question, what the coach saw and said, the circle, logs and settings.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $model.note)
                .font(.body)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
            Toggle("Include the screenshot from the last turn", isOn: $model.includeScreenshot)
                .disabled(!model.hasScreenshot)
            if !model.hasScreenshot {
                Text("No screenshot was taken for the last turn.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Saved on this Mac in: \(ProjectPaths.bugReportsFolder().path)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let error = model.errorText { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel", action: onDone)
                Button("Save report") { model.save() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func saved(_ folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Report saved", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text(folder.path).font(.callout).textSelection(.enabled)
            Text("To get it fixed, tell Claude: “read the latest bug report in bug-reports/ and fix it.”")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
    }
}
