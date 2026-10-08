import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CoachCore

/// The repository root, found from this file, so tests can read the shared assets and the Windows sources.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A fresh folder under the system temporary directory, removed when the test ends.
func withScratch(_ body: (URL) throws -> Void) rethrows {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("F2L-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}

// Same cases as TestCellIdentity in Windows/F2L.Windows.Tests/Program.cs, plus Chinese requests.
@Suite struct CellIdentity {
    @Test func referencesAreNormalised() {
        #expect(CellReference.parse("A1") == CellReference(address: "A1", row: 1, column: 1))
        #expect(CellReference.parse("b1") == CellReference(address: "B1", row: 1, column: 2))
        #expect(CellReference.parse("$AA$12") == CellReference(address: "AA12", row: 12, column: 27))
        #expect(CellReference.parse("  c7 ")?.address == "C7")
        #expect(CellReference.parse("XFD1048576")?.column == 16_384)
        #expect(CellReference.parse("AA12")?.columnLetters == "AA")
    }

    @Test(arguments: ["A0", "A1048577", "XFE1", "A1oops", "word", "A1:B1", "Sheet2!A1", "", "1A", "ABCD1"])
    func invalidOrAmbiguousCellsAreRejected(text: String) {
        #expect(CellReference.parse(text) == nil)
    }

    @Test func cellsAreFoundOnceEach() {
        #expect(CellReference.find("Compare A1 with $a$1 and B2.").map(\.address) == ["A1", "B2"])
        #expect(CellReference.find("圈出A1").map(\.address) == ["A1"])
        #expect(CellReference.find("請標記B12，謝謝").map(\.address) == ["B12"])
        #expect(CellReference.find("Sheet2!A1 or A1B2 or 2A1").isEmpty)
    }

    @Test func onlyPlainPointingRequestsSkipTheModel() {
        #expect(CellReference.isPointingOnly("please circle A1 in Excel"))
        #expect(CellReference.isPointingOnly("Can you highlight cell $B$3?"))
        #expect(CellReference.isPointingOnly("圈出A1"))
        #expect(CellReference.isPointingOnly("請圈出 A1"))
        #expect(!CellReference.isPointingOnly("what formula should I put in A1?"))
        #expect(!CellReference.isPointingOnly("circle A1 and B1"))
        #expect(!CellReference.isPointingOnly("A1"))
        #expect(!CellReference.isPointingOnly("circle A1 then type 5"))
    }

    @Test func aProposedCellMustMatchTheRequest() throws {
        let b1 = try #require(CellReference.parse("B1")), a1 = try #require(CellReference.parse("A1"))
        #expect(!CellReference.matchesRequest(b1, CellReference.find("circle A1")))
        #expect(CellReference.matchesRequest(a1, CellReference.find("circle $A$1")))
        #expect(CellReference.matchesRequest(b1, []))
        #expect(!CellReference.matchesRequest(a1, CellReference.find("A1 or B1")))
    }
}

// Same cases as TestCompanionPlacement and TestGeometry on Windows.
@Suite struct Placement {
    @Test(arguments: [1.0, 1.25, 1.5, 2])
    func pipFitsNearEdgeTargetsWithoutCoveringThem(scale: CGFloat) throws {
        let work = CGRect(x: -1600, y: -100, width: 1600 * scale, height: 900 * scale)
        for point in [CGPoint(x: work.minX + 8, y: work.minY + 8), CGPoint(x: work.maxX - 130 * scale, y: work.minY + 8),
                      CGPoint(x: work.minX + 8, y: work.maxY - 50 * scale), CGPoint(x: work.maxX - 130 * scale, y: work.maxY - 50 * scale),
                      CGPoint(x: work.midX, y: work.midY)] {
            let target = CGRect(x: point.x, y: point.y, width: 80 * scale, height: 24 * scale)
            let spot = try #require(CompanionPlacement.choose(target: target, work: work, size: CGSize(width: 112 * scale, height: 119 * scale),
                                                              panel: nil, cursor: CGPoint(x: -10_000, y: -10_000), scale: scale))
            #expect(work.contains(spot.bounds))
            #expect(!spot.bounds.touches(CompanionPlacement.protectedArea(target, scale: scale)))
        }
    }

    @Test func noSafeSpaceHidesPipInsteadOfCoveringTheTask() {
        #expect(CompanionPlacement.choose(target: CGRect(x: 20, y: 20, width: 60, height: 60), work: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          size: CGSize(width: 112, height: 119), panel: nil, cursor: CGPoint(x: -1, y: -1), scale: 1) == nil)
    }

    @Test func pipAvoidsThePanelAndPointsAtTheCell() throws {
        let cell = CGRect(x: 500, y: 350, width: 80, height: 24)
        let panel = CGRect(x: 600, y: 100, width: 500, height: 650)
        let spot = try #require(CompanionPlacement.choose(target: cell, work: CGRect(x: 0, y: 0, width: 1200, height: 800),
                                                          size: CGSize(width: 112, height: 119), panel: panel, cursor: CGPoint(x: -1, y: -1), scale: 1))
        #expect(!spot.bounds.touches(panel))
        switch spot.direction {
        case .right: #expect(spot.bounds.maxX <= cell.minX)
        case .left: #expect(spot.bounds.minX >= cell.maxX)
        case .up: #expect(spot.bounds.minY >= cell.maxY)
        case .down: #expect(spot.bounds.maxY <= cell.minY)
        case .none: Issue.record("a spot always points somewhere")
        }
    }

    @Test func thePointerPushesPipToAnotherSide() throws {
        let cell = CGRect(x: 500, y: 350, width: 80, height: 24), work = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: 112, height: 119)
        let first = try #require(CompanionPlacement.choose(target: cell, work: work, size: size, panel: nil, cursor: CGPoint(x: -1, y: -1), scale: 1))
        let moved = try #require(CompanionPlacement.choose(target: cell, work: work, size: size, panel: nil,
                                                           cursor: CGPoint(x: first.bounds.midX, y: first.bounds.midY), scale: 1))
        #expect(moved.bounds != first.bounds)
    }

    @Test func pipYieldsToThePointerAndTheTextCaret() {
        let cell = CGRect(x: 500, y: 350, width: 80, height: 24)
        let sprite = CGRect(x: 300, y: 300, width: 100, height: 110)
        #expect(CompanionPlacement.shouldYield(sprite: sprite, protectedTarget: cell, cursor: CGPoint(x: 295, y: 340), caret: nil, scale: 1))
        #expect(CompanionPlacement.shouldYield(sprite: sprite, protectedTarget: cell, cursor: CGPoint(x: -1, y: -1),
                                               caret: CGRect(x: 380, y: 330, width: 2, height: 20), scale: 1))
        #expect(CompanionPlacement.shouldYield(sprite: sprite, protectedTarget: cell, cursor: CGPoint(x: -1, y: -1),
                                               caret: CGRect(x: 430, y: 330, width: 2, height: 20), scale: 1)) // 40 points away
        #expect(!CompanionPlacement.shouldYield(sprite: sprite, protectedTarget: cell, cursor: CGPoint(x: -1, y: -1),
                                                caret: CGRect(x: 445, y: 330, width: 2, height: 20), scale: 1))
        #expect(!CompanionPlacement.shouldYield(sprite: sprite, protectedTarget: cell, cursor: CGPoint(x: 10, y: 10), caret: nil, scale: 1))
        #expect(CompanionPlacement.shouldYield(sprite: sprite, protectedTarget: CGRect(x: 400, y: 300, width: 20, height: 20),
                                               cursor: CGPoint(x: 10, y: 10), caret: nil, scale: 1)) // shares an edge with the target
    }

    @Test func edgesCountAsTouchingLikeWPF() {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(a.touches(CGRect(x: 10, y: 0, width: 5, height: 5)))
        #expect(!a.intersects(CGRect(x: 10, y: 0, width: 5, height: 5)))
        #expect(!a.touches(CGRect(x: 10.5, y: 0, width: 5, height: 5)))
        #expect(!a.touches(.null))
        #expect(a.containsIncludingEdges(CGPoint(x: 10, y: 10)))
        #expect(!a.containsIncludingEdges(CGPoint(x: 10.01, y: 10)))
    }

    @Test func screenshotTargetsKeepNegativeMonitorOrigins() {
        let rect = CompanionPlacement.fromScreenshot(window: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                                                     target: ScreenTarget(left: 100, top: 100, right: 200, bottom: 200, label: "test"))
        #expect(rect == CGRect(x: -1728, y: -92, width: 192, height: 108))
    }

    @Test func unusableGeometryIsRejected() {
        #expect(!CompanionPlacement.isUsable(.null))
        #expect(!CompanionPlacement.isUsable(CGRect(x: 0, y: 0, width: 0, height: 1)))
        #expect(!CompanionPlacement.isUsable(CGRect(x: 0, y: 0, width: 1.9, height: 20)))
        #expect(!CompanionPlacement.isUsable(CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 20)))
        #expect(CompanionPlacement.isUsable(CGRect(x: -5, y: -5, width: 2, height: 2)))
        #expect(CompanionPlacement.protectedArea(CGRect(x: 100, y: 100, width: 80, height: 20), scale: 2) == CGRect(x: 40, y: 52, width: 200, height: 116))
    }
}

// Same poses and timings as PipView.xaml.cs; TestSpriteTextures checks the same frames on Windows.
@Suite struct PipPoses {
    func pose(_ ms: Int = 0, _ change: (inout PipPose.State) -> Void) -> PipPose {
        var state = PipPose.State()
        change(&state)
        return PipPose.at(milliseconds: ms, state)
    }

    @Test func expressionsFollowTheQuestion() {
        #expect(pose { $0.intent = .multiPart } == PipPose(directions: false, frame: 4, mirrored: false))
        #expect(pose { $0.intent = .clarificationNeeded } == PipPose(directions: false, frame: 8, mirrored: false))
        #expect(pose { $0.intent = .procedural } == PipPose(directions: false, frame: 12, mirrored: false))
        #expect(pose(3_650) { $0.intent = .procedural }.frame == 13)
        #expect(pose(3_950) { $0.intent = .quickFact }.frame == 1)
        #expect(pose(4_030) { $0.intent = .quickFact }.frame == 0) // the blink cycle restarts
    }

    @Test func listeningAndThinkingOutrankSpeaking() {
        #expect(pose { $0.listening = true; $0.thinking = true }.frame == 8)
        #expect(pose(1_000) { $0.thinking = true; $0.speaking = true }.frame == 5)
        #expect(pose(190) { $0.speaking = true }.frame == 3)
    }

    @Test func pointingUsesTheDirectionSheet() {
        #expect(pose { $0.pointing = .left } == PipPose(directions: true, frame: 0, mirrored: false))
        #expect(pose { $0.pointing = .right }.frame == 2)
        #expect(pose { $0.pointing = .down }.frame == 6)
        #expect(pose(200) { $0.pointing = .down; $0.speaking = true }.frame == 7)
        #expect(pose(200) { $0.pointing = .up; $0.speaking = true }.frame == 4) // the arm stays raised
    }

    @Test func travellingWalksAndMirrorsLeft() {
        #expect(pose(170) { $0.travelling = .left; $0.pointing = .up } == PipPose(directions: true, frame: 11, mirrored: true))
        #expect(pose { $0.travelling = .right }.mirrored == false)
        #expect(pose(250) { $0.travelling = .down }.frame == 13)
    }

    @Test func reducedMotionHoldsStillPoses() {
        #expect(pose(190) { $0.speaking = true; $0.reducedMotion = true }.frame == 0)
        #expect(pose(170) { $0.travelling = .left; $0.pointing = .right; $0.reducedMotion = true } == PipPose(directions: true, frame: 2, mirrored: false))
        #expect(pose(3_950) { $0.reducedMotion = true }.frame == 0)
    }

    @Test(arguments: ["expressions", "directions"])
    func framesManifestMatchesTheArtwork(sheet: String) throws {
        let pip = repository.appendingPathComponent("Windows/F2L.Windows/Assets/Pip")
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: pip.appendingPathComponent("frames.json"))) as? [String: Any])
        let entry = try #require(manifest[sheet] as? [String: Any])
        let frames = try #require(entry["frames"] as? [[Int]])
        let source = try #require(CGImageSourceCreateWithURL(pip.appendingPathComponent("\(sheet).png") as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int), height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        #expect(entry["atlas"] as? [Int] == [width, height]) // Windows ignores a manifest made for other artwork
        #expect(frames.count == 16)
        let scale = Double(manifest["displayWidth"] as? Int ?? 0) / (Double(width) / 4)
        for f in frames {
            #expect(f.count == 4 && f[0] >= 0 && f[1] >= 0 && f[0] + f[2] <= width && f[1] + f[3] <= height)
            #expect(Double(f[2]) * scale <= 320 && Double(f[3]) * scale <= 325) // fits the 320×340 canvas above the baseline
        }
    }
}

// Same cases as TestPersistence on Windows, plus reading a file the Windows app wrote.
@Suite struct Conversations {
    @Test func onlyCompletedTurnsReachTheModel() {
        let session = ConversationSession()
        let first = session.begin("Where is A1?")
        first.text = "Column A, row 1."
        first.status = "complete"
        let stopped = session.begin("Interrupted question")
        session.stop(stopped)
        #expect(stopped.status == "stopped" && stopped.text == ConversationSession.stoppedText)
        let pending = session.begin("Pending question")
        #expect(pending.text == ConversationSession.pendingText && pending.status == "pending")
        let history = session.providerHistory(excluding: pending.turnID)
        #expect(history.map(\.role) == ["user", "assistant"])
        #expect(history.map(\.content) == ["Where is A1?", "Column A, row 1."])
    }

    @Test func historyKeepsTheNewestTwentyMessages() {
        let session = ConversationSession()
        for i in 0..<15 { let reply = session.begin("q\(i)"); reply.text = "a\(i)"; reply.status = "complete" }
        let current = session.begin("now")
        let history = session.providerHistory(excluding: current.turnID)
        #expect(history.count == 20 && history.first?.content == "q5" && history.last?.content == "a14")
    }

    @Test func savedConversationsComeBackWithTheirDraft() throws {
        try withScratch { folder in
            let store = ConversationStore(url: folder.appendingPathComponent("conversation.json"))
            let session = ConversationSession()
            let first = session.begin("Where is A1?")
            first.text = "Column A, row 1."
            first.status = "complete"
            session.stop(session.begin("Interrupted question"))
            session.begin("Pending question")
            #expect(store.save(session, draft: "draft survives"))

            let restored = ConversationSession()
            var appended: [ConversationEntry] = []
            restored.onAppend = { appended += $0 }
            #expect(store.load(into: restored) == "draft survives")
            #expect(restored.entries.count == 6 && appended.count == 6)
            #expect(restored.entries[0].text == "Where is A1?" && restored.entries[0].isUser)
            #expect(restored.entries.allSatisfy { $0.status != "pending" }) // a quit mid-reply never restores a spinner
            #expect(restored.entries[5].text == ConversationSession.stoppedText)
            #expect(restored.entries[1].createdAt.timeIntervalSince(first.createdAt).magnitude < 0.001)
        }
    }

    @Test func theBackupRecoversACorruptFile() throws {
        try withScratch { folder in
            let url = folder.appendingPathComponent("conversation.json")
            let store = ConversationStore(url: url)
            let session = ConversationSession()
            session.begin("first")
            #expect(store.save(session, draft: "older draft"))
            #expect(store.save(session, draft: "newer draft"))
            try Data("{broken".utf8).write(to: url)
            #expect(store.load(into: ConversationSession()) == "older draft")
            #expect(ConversationStore(url: folder.appendingPathComponent("missing.json")).load(into: ConversationSession()) == "")
        }
    }

    @Test func fiveHundredMessagesAreKeptInWholeTurns() throws {
        try withScratch { folder in
            let store = ConversationStore(url: folder.appendingPathComponent("conversation.json"))
            let session = ConversationSession()
            for i in 0..<263 { session.begin("question \(i)").status = "complete" }
            #expect(store.save(session, draft: ""))
            let capped = ConversationSession()
            _ = store.load(into: capped)
            #expect(capped.entries.count == 500 && capped.entries[0].isUser && capped.entries[0].text == "question 13")
        }
    }

    @Test func aFileWrittenByWindowsIsReadOnMac() throws {
        // System.Text.Json output from an older Windows build, which also wrote its display-only properties.
        let windows = #"""
            {"Version":1,"Messages":[
            {"TurnId":"5b0f4c6e-2d7c-4f43-9a51-1d5f0d4d2a10","Role":"user","CreatedAt":"2026-10-08T14:03:05.1234567+08:00","Text":"圈出A1","Status":"complete","IsUser":true,"CanReplay":false,"Author":"You","TimeLabel":"14:03","StatusLabel":""},
            {"TurnId":"5b0f4c6e-2d7c-4f43-9a51-1d5f0d4d2a10","Role":"assistant","CreatedAt":"2026-10-08T06:03:09Z","Text":"Select A1.","Status":"pending"},
            {"TurnId":"bad","Role":null,"CreatedAt":"","Text":"dropped","Status":"complete"},
            {"Role":"system","Text":"dropped too"}],
            "Draft":"half a question"}
            """#
        try withScratch { folder in
            let url = folder.appendingPathComponent("conversation.json")
            try Data(windows.utf8).write(to: url)
            let session = ConversationSession()
            #expect(ConversationStore(url: url).load(into: session) == "half a question")
            #expect(session.entries.map(\.text) == ["圈出A1", ConversationSession.stoppedText])
            #expect(session.entries[0].turnID == UUID(uuidString: "5B0F4C6E-2D7C-4F43-9A51-1D5F0D4D2A10"))
            #expect(abs(session.entries[0].createdAt.timeIntervalSince1970 - 1_791_439_385.123) < 0.0005) // seven digits, read to the millisecond
            #expect(session.entries[1].createdAt == Date(timeIntervalSince1970: 1_791_439_389))
        }
    }

    @Test func theMacWritesTheFieldsWindowsReads() throws {
        let entry = ConversationEntry(turnID: UUID(), role: "user", text: "Hi", status: "complete", createdAt: Date(timeIntervalSince1970: 1_791_439_385.5))
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        #expect(Set(object.keys) == ["TurnId", "Role", "CreatedAt", "Text", "Status"])
        #expect(object["CreatedAt"] as? String == "2026-10-08T06:03:05.500Z")
        #expect(object["TurnId"] as? String == entry.turnID.uuidString)
    }

    @Test func unknownVersionsAreIgnored() throws {
        try withScratch { folder in
            let url = folder.appendingPathComponent("conversation.json")
            try Data(#"{"Version":2,"Messages":[{"Role":"user","Text":"future"}],"Draft":"x"}"#.utf8).write(to: url)
            let session = ConversationSession()
            #expect(ConversationStore(url: url).load(into: session) == "" && session.entries.isEmpty)
        }
    }

    @Test func labelsMatchWindows() {
        let entry = ConversationEntry(turnID: UUID(), role: "assistant", text: "x", status: "error")
        #expect(entry.author == "Pip" && entry.statusLabel == "Couldn't finish" && !entry.canReplay)
        entry.status = "complete"
        #expect(entry.canReplay && entry.statusLabel == "")
        #expect(ConversationEntry(turnID: UUID(), role: "user").author == "You")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        #expect(entry.timeLabel == formatter.string(from: entry.createdAt))
    }

    @Test func editsNotifyTheView() {
        let entry = ConversationEntry(turnID: UUID())
        var changes = 0
        entry.onChange = { _ in changes += 1 }
        entry.text = "a"
        entry.status = "complete"
        #expect(changes == 2)
    }
}

// Same cases as TestDirectTeaching on Windows.
@Suite struct TeachingStyle {
    @Test func stockOpeningsAndClosingsAreRemoved() {
        #expect(TeachingReply.clean("Great question! Sure! Select A1. Let me know if you need more help.") == "Select A1.")
        #expect(TeachingReply.clean("Certainly. Click Insert. Feel free to ask any questions!") == "Click Insert.")
        #expect(TeachingReply.clean("  Sure thing: open Format Cells.  ") == "open Format Cells.")
    }

    @Test func realInstructionsArePreserved() {
        #expect(TeachingReply.clean("Enter =SUM(A1:A5). This replaces the current cell value.") == "Enter =SUM(A1:A5). This replaces the current cell value.")
        #expect(TeachingReply.clean("Select the column named Sure.") == "Select the column named Sure.")
        #expect(TeachingReply.clean("Sure!") == "Sure!") // never empty a reply
        #expect(TeachingReply.clean("Let me know if you need more help.") == "Let me know if you need more help.")
    }

    @Test func questionsPickPipsExpression() {
        #expect(QuestionIntent.classify("What is SUM?") == .quickFact)
        #expect(QuestionIntent.classify("Which one?") == .clarificationNeeded)
        #expect(QuestionIntent.classify("How do I add a pie chart?") == .procedural)
        #expect(QuestionIntent.classify("Compare VLOOKUP and XLOOKUP") == .multiPart)
        #expect(QuestionIntent.classify("What is a pivot? Why use one?") == .multiPart)
        #expect(QuestionIntent.classify("pivot tables") == .procedural)
        #expect(QuestionIntent.classify("圈出A1") == .procedural)
        #expect([QuestionIntent.quickFact, .procedural, .multiPart, .clarificationNeeded].map(\.label) == ["Friendly", "Focused", "Thinking", "Curious"])
    }
}

@Suite struct ProviderKeys {
    let none: (LocalSettings.Key) -> String = { _ in "" }

    @Test func theEnvironmentComesFirst() throws {
        try withScratch { folder in
            let file = folder.appendingPathComponent("local.settings.json")
            try Data(#"{"DeepSeekApiKey":" sk-file ","ElevenLabsApiKey":""}"#.utf8).write(to: file)
            #expect(LocalSettings.read(.deepSeek, environment: ["DEEPSEEK_API_KEY": " sk-env\n"], file: file, keychain: none) == "sk-env")
            #expect(LocalSettings.read(.deepSeek, environment: ["DEEPSEEK_API_KEY": "  "], file: file, keychain: none) == "sk-file")
            #expect(LocalSettings.read(.elevenLabs, environment: [:], file: file, keychain: { _ in " xi-keychain " }) == "xi-keychain")
            #expect(LocalSettings.read(.elevenLabs, environment: [:], file: file, keychain: none) == "")
        }
    }

    @Test(arguments: ["[1,2]", "not json", #"{"DeepSeekApiKey":42}"#, ""])
    func unreadableFilesFallBackToTheKeychain(contents: String) throws {
        try withScratch { folder in
            let file = folder.appendingPathComponent("local.settings.json")
            try Data(contents.utf8).write(to: file)
            #expect(LocalSettings.read(.deepSeek, environment: [:], file: file, keychain: { $0 == .deepSeek ? "sk-keychain" : "" }) == "sk-keychain")
        }
        #expect(LocalSettings.read(.deepSeek, environment: [:], file: nil, keychain: { _ in "sk-keychain" }) == "sk-keychain")
    }

    @Test func settingsFilesAreFoundInTheSameOrderAsWindows() throws {
        try withScratch { folder in
            let fm = FileManager.default
            let app = folder.appendingPathComponent("F2L/build/F2L.app", isDirectory: true)
            try fm.createDirectory(at: app, withIntermediateDirectories: true)
            let user = folder.appendingPathComponent("Support/F2L/local.settings.json")
            #expect(LocalSettings.settingsFile(startingAt: app, userFile: user) == nil)

            let beside = folder.appendingPathComponent("F2L/build/local.settings.json")
            try Data("{}".utf8).write(to: beside)
            #expect(LocalSettings.settingsFile(startingAt: app, userFile: user)?.path == beside.path) // a copied F2L.app

            try Data("".utf8).write(to: folder.appendingPathComponent("F2L/Package.swift"))
            let older = folder.appendingPathComponent("F2L/Windows/F2L.Windows/local.settings.json")
            try fm.createDirectory(at: older.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: older)
            #expect(LocalSettings.settingsFile(startingAt: app, userFile: user)?.path == older.path)

            let root = folder.appendingPathComponent("F2L/local.settings.json")
            try Data("{}".utf8).write(to: root)
            #expect(LocalSettings.settingsFile(startingAt: app, userFile: user)?.path == root.path)

            try fm.createDirectory(at: user.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: user)
            #expect(LocalSettings.settingsFile(startingAt: app, userFile: user)?.path == user.path)
        }
    }

    @Test func anEmptySettingsFileIsPreparedOnlyWhenNoneExists() throws {
        try withScratch { folder in
            let user = folder.appendingPathComponent("Support/F2L/local.settings.json")
            #expect(LocalSettings.prepareFile(nil, userFile: user) == user)
            let template = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: user)) as? [String: String])
            #expect(template["Provider"] == "deepseek")
            for provider in Provider.allCases { #expect(template[provider.key.fileProperty] == "" && template[provider.modelProperty] == "") }
            try Data(#"{"DeepSeekApiKey":"sk-kept"}"#.utf8).write(to: user)
            #expect(LocalSettings.prepareFile(nil, userFile: user) == user)
            #expect(LocalSettings.read(.deepSeek, environment: [:], file: user, keychain: none) == "sk-kept")
            let existing = folder.appendingPathComponent("elsewhere.json")
            #expect(LocalSettings.prepareFile(existing, userFile: user) == existing)
        }
    }
}
