import Foundation
import Testing
@testable import CoachCore

@Suite struct FreshLookAtEachStep {
    let steps = ["Open the Insert tab.", "Click Recommended Charts.", "Pick a column chart."]

    @Test func theQuestionMarksTheCurrentStepAndCarriesTheScreen() {
        let text = StepGuide.question(goal: "Make a chart", steps: steps, number: 1, platform: "macOS", app: "Microsoft Excel",
                                      screenNames: ["Recommended Charts", "Pivot Table"])
        #expect(text.contains("The learner asked: Make a chart"))
        #expect(text.contains("2. Click Recommended Charts."))
        #expect(text.contains("Current step: 2. Click Recommended Charts."))
        #expect(text.contains("The screenshot shows Microsoft Excel."))
        #expect(text.contains("Recommended Charts · Pivot Table"))
        #expect(StepGuide.question(goal: "Make a chart", steps: steps, number: 9, platform: "macOS", app: nil, screenNames: []) == "Make a chart")
    }

    @Test func repliesBecomeAPlaceAndANote() throws {
        let reply = #"{"target":{"left":300,"top":40,"right":380,"bottom":60,"label":"Recommended Charts"},"note":""}"#
        let answer = try #require(StepGuide.parse(reply))
        #expect(answer.target == ScreenTarget(left: 300, top: 40, right: 380, bottom: 60, label: "Recommended Charts"))
        #expect(answer.note.isEmpty)

        let notReady = try #require(StepGuide.parse("```json\n{\"target\":null,\"note\":\"The Insert tab is not open yet. Click Insert first.\"}\n```"))
        #expect(notReady.target == nil)
        #expect(notReady.note == "The Insert tab is not open yet. Click Insert first.")

        let cell = try #require(StepGuide.parse(#"{"target":{"cell":"B2","label":"B2","left":100,"top":100,"right":160,"bottom":120}}"#))
        #expect(cell.target?.cell == "B2")
    }

    @Test func anUnusableReplyIsNotAnAnswer() {
        #expect(StepGuide.parse("Click the Insert tab.") == nil)
        #expect(StepGuide.parse("") == nil)
        // A box that makes no sense is "no place", but the note still counts.
        #expect(StepGuide.parse(#"{"target":{"left":900,"top":0,"right":100,"bottom":50,"label":"x"},"note":"Wait for the page."}"#)
            == StepGuide.Answer(target: nil, note: "Wait for the page."))
    }

    @Test func noKeyOrNoPictureMeansNoRequest() async {
        let none = CoachClient(apiKey: { "" })
        #expect(await none.guideStep(goal: "g", steps: steps, number: 0, platform: "macOS", app: nil, screenNames: [], jpeg: Data([1])) == nil)
        let keyed = CoachClient(apiKey: { "key" })
        #expect(await keyed.guideStep(goal: "g", steps: steps, number: 0, platform: "macOS", app: nil, screenNames: [], jpeg: Data()) == nil)
        #expect(await keyed.guideStep(goal: "g", steps: steps, number: 7, platform: "macOS", app: nil, screenNames: [], jpeg: Data([1])) == nil)
    }
}
