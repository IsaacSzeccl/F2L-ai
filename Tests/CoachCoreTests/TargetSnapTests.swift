import CoreGraphics
import Testing
@testable import CoachCore

@Suite struct PointingAtTheRightPlace {
    let ribbon = [ControlCandidate(frame: CGRect(x: 100, y: 60, width: 44, height: 22), name: "Home"),
                  ControlCandidate(frame: CGRect(x: 150, y: 60, width: 44, height: 22), name: "Insert"),
                  ControlCandidate(frame: CGRect(x: 420, y: 90, width: 40, height: 56), name: "Insert Pie or Doughnut Chart"),
                  ControlCandidate(frame: CGRect(x: 0, y: 0, width: 1400, height: 900), name: "Book1")]

    @Test func roughBoxesSnapToTheNamedControl() {
        // The model was 30 points off; the Insert tab itself is circled.
        #expect(TargetSnap.snap(box: CGRect(x: 175, y: 75, width: 40, height: 20), label: "Insert tab", candidates: ribbon)
                == CGRect(x: 150, y: 60, width: 44, height: 22))
        #expect(TargetSnap.snap(box: CGRect(x: 400, y: 100, width: 30, height: 30), label: "Pie chart", candidates: ribbon)
                == CGRect(x: 420, y: 90, width: 40, height: 56))
        // Without a box, only one exact name is trusted.
        #expect(TargetSnap.snap(box: nil, label: "Home", candidates: ribbon) == CGRect(x: 100, y: 60, width: 44, height: 22))
    }

    @Test func unnamedSpotsUseTheControlUnderThemOnlyWhenTheSizeFits() {
        #expect(TargetSnap.snap(box: CGRect(x: 152, y: 62, width: 38, height: 18), label: "Next step", candidates: ribbon)
                == CGRect(x: 150, y: 60, width: 44, height: 22))
        // The whole window is under every point, but it isn't what the model meant.
        #expect(TargetSnap.snap(box: CGRect(x: 700, y: 500, width: 30, height: 20), label: "Next step", candidates: ribbon) == nil)
        #expect(TargetSnap.normalise("“Insert” tab") == "insert")
    }

    @Test func theCircleSurroundsTheWholeTarget() {
        let cell = CGRect(x: 100, y: 100, width: 64, height: 20)
        let circle = TargetSnap.circle(around: cell)
        for corner in [CGPoint(x: cell.minX, y: cell.minY), CGPoint(x: cell.maxX, y: cell.maxY)] {
            let dx = (corner.x - circle.midX) / (circle.width / 2), dy = (corner.y - circle.midY) / (circle.height / 2)
            #expect(dx * dx + dy * dy < 1)
        }
    }

    @Test func excelCellsArePlacedFromExcelsOwnNumbers() {
        // B3 at 100% zoom on a sheet scrolled to A1, grid frame at (200, 300), headings drawn outside the frame.
        let metrics = ExcelCellMetrics(visibleLeft: 0, visibleTop: 0, left: 64, top: 40, width: 64, height: 20, zoom: 100, headings: false)
        let grid = CGRect(x: 200, y: 300, width: 900, height: 600)
        let candidates = ExcelGeometry.candidates(metrics, grid: grid)
        #expect(candidates.first == CGRect(x: 264, y: 340, width: 64, height: 20))
        // The model's rough box decides between 72 and 96 dpi drawing.
        #expect(ExcelGeometry.choose(candidates, near: CGRect(x: 262, y: 338, width: 66, height: 22)) == CGRect(x: 264, y: 340, width: 64, height: 20))
        #expect(ExcelGeometry.choose(candidates, near: CGRect(x: 800, y: 800, width: 60, height: 20)) == nil)
        #expect(ExcelGeometry.choose(candidates, near: nil) == nil) // two possible placements, no way to tell
    }
}
