import Foundation
import Testing
@testable import CoachCore

@Suite struct CompanionFlow {
    @Test func disconnectedSelectionIsKeptExact() throws {
        let context = try #require(ExcelContext(sheet: "Budget", selection: "$A$1:$A$4, $D$1:$D$4", activeCell: "$D$1"))
        #expect(context.areas == ["A1:A4", "D1:D4"])
        #expect(context.displayLine == "Excel has selected A1:A4, D1:D4 · Budget")
        #expect(CoachClient.compose(question: "Make a chart", platform: "macOS", excel: context).contains("2 separate areas"))
        #expect(ExcelContext(sheet: "Sheet1", selection: " , ", activeCell: "") == nil)
    }

    @Test func stepsSurviveParsingAndHistory() throws {
        let answer = try #require(try CoachClient.readReply(#"{"reply":"Select both groups.","steps":["Click A1.","Hold Command and drag D1:D4.","",7],"target":null}"#))
        #expect(answer.steps == ["Click A1.", "Hold Command and drag D1:D4."])
        #expect(answer.text == "Select both groups.\n\n1. Click A1.\n2. Hold Command and drag D1:D4.")
        #expect(ReplyPhrases.pages(reply: answer.reply, steps: answer.steps) == ["Select both groups.", "1. Click A1.", "2. Hold Command and drag D1:D4."])
        let session = ConversationSession()
        let entry = session.begin("Select two groups")
        entry.text = answer.text; entry.status = "complete"
        let next = session.begin("What next?")
        #expect(session.providerHistory(excluding: next.turnID).last?.content == answer.text)
    }

    @Test func animationRangesPreserveUnicodeAndFormulas() {
        let text = "請選 A1 👋🏽\nType =SUM(A1:A4,D1:D4)."
        let pieces = ReplyPhrases.words(in: text).map { (text as NSString).substring(with: $0) }
        #expect(pieces.joined() == text)
        #expect(pieces.last == "=SUM(A1:A4,D1:D4).")
        #expect(ReplyPhrases.pages(reply: "Type =ROUND(A1, 2).", steps: []) == ["Type =ROUND(A1, 2)."])
    }

    @Test func newSessionsLeavePreviousFilesUntouched() throws {
        try withScratch { folder in
            let legacy = ConversationStore(url: folder.appendingPathComponent("conversation.json"))
            let previous = ConversationSession()
            let reply = previous.begin("Old question"); reply.text = "Old reply"; reply.status = "complete"
            #expect(legacy.save(previous, draft: "Keep my draft"))
            let original = try Data(contentsOf: legacy.url)
            let fresh = legacy.nextSession(), empty = ConversationSession()
            #expect(fresh.save(empty, draft: ""))
            #expect(try Data(contentsOf: legacy.url) == original)
            #expect(empty.providerHistory(excluding: UUID()).isEmpty)
            #expect(fresh.nextSession().url.deletingLastPathComponent() == fresh.url.deletingLastPathComponent())
            #expect(fresh.nextSession().url != fresh.url)
        }
    }

    @Test func selectionStepsAreTickedFromExcelsRealSelection() {
        #expect(StepCheck.references(in: "Hold Command and drag from D1 to D4.") == ["D1:D4"])
        #expect(StepCheck.references(in: "Select A1-A4, then type =SUM(B1:B4) in C1.") == ["A1:A4", "C1"])
        let first = "Click A1, then hold Shift and click A4."
        #expect(StepCheck.check(step: first, selected: ["A1"]) == .missing(["A4"]))
        #expect(StepCheck.check(step: first, selected: ["A1:A4"]) == .done)
        let second = "Hold Command and drag from D1 to D4."
        #expect(StepCheck.check(step: second, earlier: [first], selected: ["A1:A4", "D1:D4"]) == .done)
        // Forgetting to hold Command drops the first range, and Pip says so.
        #expect(StepCheck.check(step: second, earlier: [first], selected: ["D1:D4"]) == .missing(["A1", "A4"]))
        #expect(StepCheck.check(step: "Open Insert and choose a chart.", selected: ["A1:A4"]) == .notCheckable)
        #expect(StepCheck.check(step: "Type =SUM(A1:A4) and press Return.", selected: []) == .notCheckable)
    }

    @Test func eachStepCanSayWhereItHappens() throws {
        let answer = try #require(try CoachClient.readReply(#"{"reply":"Make a chart.","steps":[{"text":"Select A1:A4.","target":{"cell":"A1:A4","label":"A1:A4","left":100,"top":200,"right":160,"bottom":300}},{"text":"Open the Insert tab.","target":{"left":300,"top":40,"right":350,"bottom":60,"label":"Insert"}},"Choose a pie chart."],"check":null,"target":null}"#))
        #expect(answer.steps == ["Select A1:A4.", "Open the Insert tab.", "Choose a pie chart."])
        #expect(answer.stepTargets.count == 3)
        #expect(answer.stepTargets[0] == ScreenTarget(left: 100, top: 200, right: 160, bottom: 300, label: "A1:A4", cell: "A1"))
        #expect(answer.stepTargets[1] == ScreenTarget(left: 300, top: 40, right: 350, bottom: 60, label: "Insert"))
        #expect(answer.stepTargets[2] == nil)
        #expect(answer.stepTargets[0]?.hasBox == true)
        // A cell with no box is still named, but there is nowhere to draw until Excel confirms it.
        let named = try #require(try CoachClient.readReply(#"{"reply":"Select A1.","steps":[],"check":null,"target":{"cell":"A1","label":"A1"}}"#))
        #expect(named.target?.cell == "A1" && named.target?.hasBox == false)
    }
}
