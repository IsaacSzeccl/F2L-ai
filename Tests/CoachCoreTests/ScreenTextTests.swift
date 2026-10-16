import CoreGraphics
import Testing
@testable import CoachCore

@Suite struct ReadingTheScreen {
    /// Excel-like headings: columns 64 wide starting at x=100 (A centred at 132), rows 20 high starting at y=200.
    func sheet() -> [ScreenWord] {
        var words: [ScreenWord] = []
        for (i, letter) in ["A", "B", "C", "D", "E", "F"].enumerated() {
            words.append(ScreenWord(text: letter, frame: CGRect(x: 100 + CGFloat(i) * 64 + 28, y: 182, width: 8, height: 12)))
        }
        for row in 1...10 {
            words.append(ScreenWord(text: "\(row)", frame: CGRect(x: 70, y: 200 + CGFloat(row - 1) * 20 + 4, width: 12, height: 12)))
        }
        // Stray text inside cells must not be taken for headings.
        words.append(ScreenWord(text: "B", frame: CGRect(x: 300, y: 260, width: 8, height: 12)))
        words.append(ScreenWord(text: "42", frame: CGRect(x: 360, y: 300, width: 14, height: 12)))
        return words
    }

    @Test func cellsAreFoundWhereTheirHeadingsMeet() throws {
        let d3 = try #require(ScreenText.excelCell("D3", words: sheet()))
        #expect(abs(d3.minX - 292) < 0.5 && abs(d3.width - 64) < 0.5)
        #expect(abs(d3.minY - 240) < 0.5 && abs(d3.height - 20) < 0.5)
        let range = try #require(ScreenText.excelCell("A1:A4", words: sheet()))
        #expect(abs(range.minX - 100) < 0.5 && abs(range.height - 80) < 0.5)
        #expect(ScreenText.excelCell("Z99", words: sheet()) == nil) // not on screen: no guess
    }

    @Test func misreadOrMissingHeadingsStillPlaceTheCell() throws {
        // Reading single letters is unreliable: A and E are missed, C comes back lower case, rows 3 and 6 are missed.
        let columns: [ScreenWord] = ["B", "c", "D", "F"].map { letter in
            let index: Int = Int(letter.uppercased().unicodeScalars.first!.value) - 65
            let x: CGFloat = 100 + CGFloat(index) * 64 + 28
            return ScreenWord(text: letter, frame: CGRect(x: x, y: 182, width: 8, height: 12))
        }
        let rows: [ScreenWord] = [1, 2, 4, 5, 7].map { (row: Int) in
            let y: CGFloat = 200 + CGFloat(row - 1) * 20 + 4
            return ScreenWord(text: "\(row)", frame: CGRect(x: 70, y: y, width: 12, height: 12))
        }
        let words: [ScreenWord] = columns + rows
        let d3 = try #require(ScreenText.excelCell("D3", words: words))
        #expect(abs(d3.minX - 292) < 0.5 && abs(d3.minY - 240) < 0.5 && abs(d3.width - 64) < 0.5 && abs(d3.height - 20) < 0.5)
    }

    @Test func aStrayWordUnderTheSpotIsNotTheButton() {
        // From the owner's test: "Fill" is an icon with no visible name; a "2" read near the model's spot was circled.
        let read = [ControlCandidate(frame: CGRect(x: 1140, y: 140, width: 30, height: 24), name: "2")]
        #expect(TargetSnap.snap(box: CGRect(x: 1142, y: 150, width: 42, height: 26), label: "Fill", candidates: read, byPosition: false) == nil)
    }

    @Test func neighbouringWordsNameOneButton() {
        let line = [ScreenWord(text: "Recommended", frame: CGRect(x: 10, y: 10, width: 80, height: 12)),
                    ScreenWord(text: "Charts", frame: CGRect(x: 94, y: 10, width: 40, height: 12)),
                    ScreenWord(text: "Maps", frame: CGRect(x: 300, y: 10, width: 30, height: 12))]
        let candidates = ScreenText.candidates(lines: [line])
        #expect(candidates.contains(ControlCandidate(frame: CGRect(x: 10, y: 10, width: 124, height: 12), name: "Recommended Charts")))
        #expect(!candidates.contains { $0.name == "Charts Maps" }) // far apart: different controls
        #expect(TargetSnap.snap(box: CGRect(x: 400, y: 400, width: 20, height: 20), label: "Recommended Charts", candidates: candidates)
                == CGRect(x: 10, y: 10, width: 124, height: 12))
    }
}
