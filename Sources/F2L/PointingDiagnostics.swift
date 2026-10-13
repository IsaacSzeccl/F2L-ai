import AppKit
import ApplicationServices
import CoachCore

/// A local record of how Pip decided where to point, so a wrong circle can be debugged from facts instead of guesses.
/// Nothing leaves the computer: decisions go to ~/Library/Application Support/F2L/pointing.log (no pictures), and
/// "Save pointing diagnostics" in Pip's menu writes one snapshot folder the owner chose to make.
enum PointingDiagnostics {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("F2L", isDirectory: true)
    static var log: URL { folder.appendingPathComponent("pointing.log") }

    static func rect(_ r: CGRect?) -> [String: Double]? {
        r.map { ["x": Double($0.minX), "y": Double($0.minY), "w": Double($0.width), "h": Double($0.height)] }
    }

    /// One line per pointing decision; the file is trimmed to its last 200 KB.
    static func record(_ fields: [String: Any]) {
        var entry = fields
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var existing = (try? Data(contentsOf: log)) ?? Data()
        existing.append(data)
        existing.append(0x0A)
        if existing.count > 200_000 { existing = existing.suffix(150_000) }
        try? existing.write(to: log)
    }

    /// What Accessibility reports at `point`: role and frame of the deepest element.
    static func elementAt(_ point: CGPoint, pid: pid_t) -> [String: Any] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success, let element else {
            return ["point": ["x": point.x, "y": point.y], "found": false]
        }
        var info: [String: Any] = ["point": ["x": point.x, "y": point.y]]
        for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXRoleDescriptionAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let value = DesktopAccessibility.attribute(element, name) as? String { info[name] = value }
        }
        info["frame"] = rect(DesktopAccessibility.frame(element))
        if let parent = DesktopAccessibility.attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
            let parent = parent as! AXUIElement
            info["parentRole"] = DesktopAccessibility.attribute(parent, kAXRoleAttribute) as? String
            info["parentFrame"] = rect(DesktopAccessibility.frame(parent))
        }
        return info
    }

    /// Writes a snapshot of the front app for debugging pointing: its window, a picture of it, what Accessibility
    /// reports (named controls, the Excel grid, elements under sample points) and Excel's own cell numbers.
    @MainActor
    static func save(app: ForegroundApp?, capture: ScreenCaptureService, excel: ExcelSelectionReader) async -> String {
        guard let app else { return "Click the app you want help with once, then choose Save pointing diagnostics again." }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let out = folder.appendingPathComponent("diagnostics", isDirectory: true).appendingPathComponent(stamp, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var report: [String: Any] = ["app": app.name, "bundle": app.bundleID ?? "", "accessibilityTrusted": DesktopAccessibility.isTrusted,
                                     "screens": NSScreen.screens.map { ["frame": rect(ScreenSpace.toTopLeft($0.frame)) ?? [:], "scale": $0.backingScaleFactor] }]
        do {
            let shot = try await capture.capture(app)
            report["window"] = rect(shot.frame)
            try? shot.jpeg.write(to: out.appendingPathComponent("window.jpg"))
            let pid = app.pid, window = shot.frame
            let (controls, grid, samples) = await Task.detached { () -> ([ControlCandidate], CGRect?, [[String: Any]]) in
                let controls = DesktopAccessibility.controls(pid: pid, in: window)
                let grid = DesktopAccessibility.largest(role: "AXLayoutArea", pid: pid, in: window)
                let area = grid ?? window
                let points = [(0.02, 0.02), (0.1, 0.05), (0.5, 0.5), (0.02, 0.5), (0.5, 0.02)].map {
                    CGPoint(x: area.minX + area.width * $0.0, y: area.minY + area.height * $0.1)
                }
                return (controls, grid, points.map { elementAt($0, pid: pid) })
            }.value
            report["controls"] = controls.prefix(600).map { ["name": $0.name, "frame": rect($0.frame) ?? [:]] }
            report["excelGrid"] = rect(grid)
            report["elementsAt"] = samples
        } catch {
            report["captureError"] = (error as? ScreenCaptureError)?.message ?? "\(error)"
        }
        if app.isExcel {
            var cells: [String: Any] = [:]
            for address in ["A1", "B2", "C5"] {
                if let m = await excel.cellMetrics(address) {
                    cells[address] = ["visibleLeft": m.visibleLeft, "visibleTop": m.visibleTop, "left": m.left, "top": m.top,
                                      "width": m.width, "height": m.height, "zoom": m.zoom, "headings": m.headings]
                }
            }
            report["excelCells"] = cells
            report["excelSelection"] = await excel.read().message
        }
        report["recentPointing"] = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").suffix(30).map(String.init) ?? []
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("report.json"))
        }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        return "Saved pointing diagnostics. Tell Claude it's in F2L › diagnostics › \(stamp)."
    }
}
