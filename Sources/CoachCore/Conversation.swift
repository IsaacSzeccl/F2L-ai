import Foundation

/// One message in Pip's conversation. Field names and values match the Windows JSON file
/// (Windows/F2L.Windows/ConversationSession.cs), so both apps read and write the same format.
public final class ConversationEntry: Codable, Identifiable, @unchecked Sendable {
    public var turnID: UUID
    public var role: String
    public var createdAt: Date
    public var text: String { didSet { onChange?(self) } }
    public var status: String { didSet { onChange?(self) } }
    /// Called whenever text or status changes, so the view can refresh just this message.
    public var onChange: ((ConversationEntry) -> Void)?

    public init(turnID: UUID, role: String = "assistant", text: String = "", status: String = "complete", createdAt: Date = Date()) {
        self.turnID = turnID
        self.role = role
        self.text = text
        self.status = status
        self.createdAt = createdAt
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public var isUser: Bool { role == "user" }
    public var canReplay: Bool { role == "assistant" && status == "complete" }
    public var author: String { isUser ? "You" : "Pip" }
    public var statusLabel: String {
        switch status {
        case "pending": "Thinking"
        case "stopped": "Stopped"
        case "error": "Couldn't finish"
        default: ""
        }
    }
    public var timeLabel: String { Self.timeFormatter.string(from: createdAt) }

    // One shared formatter: making a DateFormatter per message is slow. Formatting is thread-safe.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case turnID = "TurnId", role = "Role", createdAt = "CreatedAt", text = "Text", status = "Status"
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        turnID = (try? c.decode(UUID.self, forKey: .turnID)) ?? UUID()
        // Like System.Text.Json: a missing role keeps the default, a null one is dropped on load.
        role = c.contains(.role) ? ((try? c.decode(String.self, forKey: .role)) ?? "") : "assistant"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? "complete"
        let stamp = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        createdAt = ConversationDates.parse(stamp) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(turnID, forKey: .turnID)
        try c.encode(role, forKey: .role)
        try c.encode(ConversationDates.format(createdAt), forKey: .createdAt)
        try c.encode(text, forKey: .text)
        try c.encode(status, forKey: .status)
    }
}

/// .NET writes DateTimeOffset with up to seven fractional digits; ISO8601DateFormatter accepts at most three.
enum ConversationDates {
    // ISO8601DateFormatter is thread-safe once configured.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ text: String) -> Date? {
        var value = text
        if let dot = value.firstIndex(of: "."),
           let zone = value[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let digits = value[value.index(after: dot)..<zone]
            value.replaceSubrange(value.index(after: dot)..<zone, with: String(digits.prefix(3)))
        }
        return fractional.date(from: value) ?? plain.date(from: text)
    }

    static func format(_ date: Date) -> String { fractional.string(from: date) }
}

/// The ordered conversation and its turn bookkeeping. Mirrors ConversationSession.cs.
public final class ConversationSession {
    public static let pendingText = "Thinking…"
    static let stoppedText = "Reply stopped. Your question is still here; you can continue below."
    public private(set) var entries: [ConversationEntry] = []
    /// Called after entries are added (not for edits; those use ConversationEntry.onChange).
    public var onAppend: (([ConversationEntry]) -> Void)?

    public init() {}

    @discardableResult
    public func begin(_ question: String) -> ConversationEntry {
        let turn = UUID()
        let user = ConversationEntry(turnID: turn, role: "user", text: question)
        let reply = ConversationEntry(turnID: turn, text: Self.pendingText, status: "pending")
        entries += [user, reply]
        onAppend?([user, reply])
        return reply
    }

    public func load(_ restored: [ConversationEntry]) {
        for entry in restored { stop(entry) }
        entries += restored
        onAppend?(restored)
    }

    public func stop(_ entry: ConversationEntry?) {
        guard let entry, entry.status == "pending" else { return }
        entry.text = Self.stoppedText
        entry.status = "stopped"
    }

    /// Completed earlier turns, newest twenty messages, for the model's context.
    public func providerHistory(excluding currentTurn: UUID) -> [(role: String, content: String)] {
        let complete = Set(entries.filter { $0.role == "assistant" && $0.status == "complete" && $0.turnID != currentTurn }.map(\.turnID))
        return entries.filter { complete.contains($0.turnID) }.suffix(20).map { ($0.role, $0.text) }
    }
}

/// Saves the latest 500 messages and the unsent draft, with a backup copy. Mirrors ConversationStore in C#.
public struct ConversationStore {
    public let url: URL
    private struct Document: Codable {
        var version: Int
        var messages: [ConversationEntry]
        var draft: String
        enum CodingKeys: String, CodingKey { case version = "Version", messages = "Messages", draft = "Draft" }
    }

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("F2L", isDirectory: true).appendingPathComponent("conversation.json")
    }

    public static func fresh() -> ConversationStore { ConversationStore().nextSession() }

    public func nextSession() -> ConversationStore {
        let parent = url.deletingLastPathComponent()
        let folder = parent.lastPathComponent == "sessions" ? parent : parent.appendingPathComponent("sessions", isDirectory: true)
        return ConversationStore(url: folder.appendingPathComponent("\(UUID().uuidString).json"))
    }

    /// Restores messages into `session` and returns the saved draft.
    public func load(into session: ConversationSession) -> String {
        let backup = url.appendingPathExtension("bak")
        for candidate in [url, backup] {
            guard let data = try? Data(contentsOf: candidate),
                  let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1 else { continue }
            session.load(Array(document.messages.filter { $0.role == "user" || $0.role == "assistant" }.suffix(500)))
            return document.draft
        }
        return ""
    }

    @discardableResult
    public func save(_ session: ConversationSession, draft: String) -> Bool {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Document(version: 1, messages: Array(session.entries.suffix(500)), draft: draft))
            let temp = url.appendingPathExtension("tmp")
            try data.write(to: temp)
            let backup = url.appendingPathExtension("bak")
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: url, to: backup)
            }
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temp) }
            else { try fm.moveItem(at: temp, to: url) }
            return true
        } catch {
            return false
        }
    }
}
