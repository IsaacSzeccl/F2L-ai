import Foundation
import CoreGraphics
import Testing
@testable import CoachCore

// Same cases as TestClickWatch on Windows.
@Suite struct ClickWatching {
    let place = CGRect(x: 100, y: 100, width: 80, height: 24)

    @Test func aPressOnTheCircleCountsOnce() {
        var watch = ClickWatch()
        do { let hit = watch.pressed(false, at: CGPoint(x: 140, y: 112), target: place); #expect(!hit) }
        do { let hit = watch.pressed(true, at: CGPoint(x: 140, y: 112), target: place); #expect(hit) }
        // Holding the button is still the same click.
        do { let hit = watch.pressed(true, at: CGPoint(x: 140, y: 112), target: place); #expect(!hit) }
        do { let hit = watch.pressed(false, at: CGPoint(x: 140, y: 112), target: place); #expect(!hit) }
        // A press just outside the drawn circle still counts; one far away doesn't.
        do { let hit = watch.pressed(true, at: CGPoint(x: 92, y: 112), target: place); #expect(hit) }
        _ = watch.pressed(false, at: .zero, target: place)
        do { let hit = watch.pressed(true, at: CGPoint(x: 400, y: 400), target: place); #expect(!hit) }
    }

    @Test func pressesOnPipOrWithNothingCircledDoNotCount() {
        var watch = ClickWatch()
        do { let hit = watch.pressed(true, at: CGPoint(x: 140, y: 112), target: nil); #expect(!hit) }
        _ = watch.pressed(false, at: .zero, target: place)
        do { let hit = watch.pressed(true, at: CGPoint(x: 140, y: 112), target: place, ignoring: [CGRect(x: 120, y: 100, width: 50, height: 50)]); #expect(!hit) }
    }

    @Test(arguments: [("Click New page.", true), ("Open the Insert tab.", true), ("Type your email in the box.", false),
                      ("Drag from A1 to A4.", false), ("Hold Command and click D1.", true), ("Hold Command and drag from D1 to D4.", false),
                      ("Paste the text.", false)])
    func onlyClickStepsFinishOnAClick(step: String, finishes: Bool) {
        #expect(ClickWatch.finishesOnClick(step) == finishes)
    }

    @Test func keysToHoldAndTypingStepsAreRead() {
        #expect(ClickWatch.requiredKeys("Click A1, then hold Shift and click A4.") == ["shift"])
        #expect(ClickWatch.requiredKeys("Hold down the Command key while you click D1.") == ["command"])
        #expect(ClickWatch.requiredKeys("Hold Ctrl and click D1.") == ["control"] && ClickWatch.requiredKeys("Hold Alt and click.") == ["option"])
        #expect(ClickWatch.requiredKeys("Click New page.").isEmpty)
        #expect(ClickWatch.isTypingStep("Type your email in the box.") && ClickWatch.isTypingStep("Enter 100 in B2."))
        #expect(!ClickWatch.isTypingStep("Click Share."))
    }

    @Test func typingTicksOnceTheBoxHasNewTextAndTheLearnerPauses() {
        typealias F = TypingWatch.Fingerprint
        var watch = TypingWatch()
        let start = Date()
        do { let done = watch.observe(F(length: 0, hash: 1), at: start); #expect(!done) } // the empty box when the step began
        do { let done = watch.observe(F(length: 3, hash: 2), at: start + 0.5); #expect(!done) } // typing
        do { let done = watch.observe(F(length: 5, hash: 3), at: start + 1.0); #expect(!done) }
        do { let done = watch.observe(F(length: 5, hash: 3), at: start + 2.0); #expect(!done) } // a short pause
        do { let done = watch.observe(F(length: 5, hash: 3), at: start + 2.6); #expect(done) } // stopped typing
        do { let done = watch.observe(F(length: 5, hash: 3), at: start + 4.0); #expect(!done) } // counted once
        // Text that was already there, or an emptied box, doesn't count.
        var unchanged = TypingWatch()
        _ = unchanged.observe(F(length: 4, hash: 9), at: start)
        do { let done = unchanged.observe(F(length: 4, hash: 9), at: start + 5); #expect(!done) }
        var emptied = TypingWatch()
        _ = emptied.observe(F(length: 4, hash: 9), at: start)
        _ = emptied.observe(F(length: 0, hash: 1), at: start + 1)
        do { let done = emptied.observe(F(length: 0, hash: 1), at: start + 5); #expect(!done) }
    }

    @Test func screenNamesAreTidyAndBounded() {
        let names = ScreenNames.pick(["Share", "share", " New page ", "x", "12", String(repeating: "a", count: 50), "Insert"]
                                     + (0..<200).map { "Item \($0)" })
        #expect(Array(names.prefix(3)) == ["Share", "New page", "Insert"] && names.count == ScreenNames.limit)
        #expect(ScreenNames.line([]) == "")
        #expect(ScreenNames.line(["Share"]).hasSuffix(": Share"))
        #expect(CoachClient.compose(question: "Q", platform: "macOS", excel: nil, screenNames: ["Share", "New page"])
            .contains("(Learner's computer: macOS.)\nNames visible in the screenshot"))
    }
}
