import Testing
@testable import CoachCore

// Same cases as TestNamedPlaces on Windows.
@Suite struct NamedPlaces {
    @Test(arguments: [
        ("Click the Japan tile in the Recents row.", "Japan"),
        ("Open the Insert tab.", "Insert"),
        ("Click Pause for 15 min to stop for a while.", "Pause"),
        ("You can find it in the Home tab.", "Home"),
        ("Choose \u{201C}Recommended Charts\u{201D} from the list.", "Recommended Charts"),
        ("Hold Shift and click A4.", "A4"),
        ("Select A1:A4 first.", "A1:A4"),
    ])
    func findsTheNamedPlace(text: String, name: String) {
        #expect(NamedPlace.label(in: text) == name)
    }

    @Test(arguments: [
        "This is a VPN app window. It shows you connected through Melbourne.",
        "Press Command+C to copy.",
        "Click the empty cell under your numbers, then type =SUM(B2:B10).",
        "Hold Command and drag from D1 to D4.",
    ])
    func namesNothingWhenThereIsNothingToCircle(text: String) {
        #expect(NamedPlace.label(in: text) == nil)
    }

    @Test func cellsAndRangesAreCheckedWithExcel() {
        #expect(NamedPlace.target(in: "Click A4.")?.cell == "A4")
        #expect(NamedPlace.target(in: "Select A1:A4.")?.cell == "A1")
        #expect(NamedPlace.target(in: "Open the Insert tab.")?.cell == nil)
        #expect(NamedPlace.target(in: "Open the Insert tab.")?.hasBox == false)
    }

    @Test func stepsWithoutAPlaceStillPointSomewhere() {
        let japan = ScreenTarget(left: 1, top: 1, right: 9, bottom: 9, label: "Japan")
        let insert = ScreenTarget(left: 2, top: 2, right: 8, bottom: 8, label: "Insert")
        // The only step borrows the reply's place.
        #expect(CoachAnswer(reply: "Switch to Japan.", steps: ["Click the Japan tile."], target: japan).placesForSteps == [japan])
        // A step that names the reply's place borrows it; another step is found by its own name; a step's own place wins.
        let answer = CoachAnswer(reply: "Insert a chart.", steps: ["Open the Insert tab.", "Click Recommended Charts.", "Click OK."],
                                 stepTargets: [nil, nil, japan], target: insert)
        let places = answer.placesForSteps
        #expect(places[0] == insert && places[1]?.label == "Recommended Charts" && places[2] == japan)
        // A plain reply that tells the learner to act on something points at it; one that only describes doesn't.
        #expect(CoachAnswer(reply: "Click the Japan tile in the Recents row.", target: nil).placeForReply?.label == "Japan")
        #expect(CoachAnswer(reply: "This is a VPN app.", target: nil).placeForReply == nil)
        #expect(CoachAnswer(reply: "Open Insert.", target: japan).placeForReply == japan)
    }
}
