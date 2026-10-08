import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenCaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The app being taught: the last regular app the learner used, other than F2L.
struct ForegroundApp: Equatable {
    let pid: pid_t
    let name: String
    var bundleID: String?
    /// Desktop Excel, whose cells F2L verifies instead of trusting a screenshot rectangle (XLMAIN on Windows).
    var isExcel: Bool { bundleID == "com.microsoft.Excel" }
}

/// A single window image, held in memory only. `frame` is global, top-left, in points.
/// A cell-pointing request only needs the window, so its `jpeg` is empty.
final class CapturedScreen {
    var jpeg: Data
    let windowID: CGWindowID
    let frame: CGRect
    let app: ForegroundApp

    init(jpeg: Data, windowID: CGWindowID, frame: CGRect, app: ForegroundApp) {
        self.jpeg = jpeg
        self.windowID = windowID
        self.frame = frame
        self.app = app
    }
}

/// Remembers which app the learner is using (identity only; nothing is captured in the background)
/// and captures that app's front window when a question is sent.
@MainActor
final class ScreenCaptureService {
    private static let maxImageSide = 1800.0 // same limit as Windows
    private var last: ForegroundApp?
    private var observer: Any?

    func startTracking() {
        rememberForeground()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.observe(app) }
        }
    }

    func stopTracking() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        last = nil
    }

    func rememberForeground() { observe(NSWorkspace.shared.frontmostApplication) }

    private func observe(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !app.isTerminated else { return }
        last = ForegroundApp(pid: app.processIdentifier, name: app.localizedName ?? "the app", bundleID: app.bundleIdentifier)
    }

    func target() -> ForegroundApp? {
        rememberForeground()
        if let last, NSRunningApplication(processIdentifier: last.pid)?.isTerminated != false { self.last = nil }
        return last
    }

    /// The app's main window: id and global top-left frame in points. A small popup in front of it (Zoom's
    /// "Start Zoom AI" card, a tooltip window) is skipped: the frontmost window at least half the size of the app's
    /// biggest window wins.
    nonisolated static func frontWindow(of pid: pid_t) -> (CGWindowID, CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let windows: [(CGWindowID, CGRect)] = list.compactMap { info in // front to back
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid, (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.width > 40, bounds.height > 40,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return (id, bounds)
        }
        let biggest = windows.map { $0.1.width * $0.1.height }.max() ?? 0
        return windows.first { $0.1.width * $0.1.height >= biggest * 0.5 }
    }

    /// The window's current frame, or nil if it closed, minimised or left the screen.
    nonisolated static func currentFrame(of window: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], window) as? [[String: Any]],
              let info = list.first, (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: boundsDict)
    }

    /// Whether the captured window is still open, on screen and in front of other apps, like NativeDesktop.IsSourceCurrent.
    /// F2L itself being frontmost (Settings, a menu) doesn't count as leaving the app.
    static func isSourceCurrent(_ capture: CapturedScreen) -> Bool {
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           front != capture.app.pid, front != ProcessInfo.processInfo.processIdentifier { return false }
        return currentFrame(of: capture.windowID) != nil
    }

    /// Whether the captured window is still where it was, so a highlight drawn from it is still meaningful.
    static func isCurrent(_ capture: CapturedScreen) -> Bool {
        guard isSourceCurrent(capture), let frame = currentFrame(of: capture.windowID) else { return false }
        return abs(frame.minX - capture.frame.minX) < 1 && abs(frame.minY - capture.frame.minY) < 1 &&
            abs(frame.width - capture.frame.width) < 1 && abs(frame.height - capture.frame.height) < 1
    }

    /// The same window at its current position, for re-checking a verified cell after the window moves.
    static func refreshed(_ capture: CapturedScreen) -> CapturedScreen? {
        guard isSourceCurrent(capture), let frame = currentFrame(of: capture.windowID), frame.width >= 2, frame.height >= 2 else { return nil }
        return CapturedScreen(jpeg: Data(), windowID: capture.windowID, frame: frame, app: capture.app)
    }

    /// Whether `point` shows the given window rather than another app's window in front of it (WindowFromPoint on
    /// Windows). F2L's own windows are ignored; the panel has already moved away from the target.
    nonisolated static func pointBelongsToWindow(_ window: CGWindowID, _ point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list { // front to back
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0, layer < Int(CGWindowLevelForKey(.dockWindow)),
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.contains(point) else { continue }
            return (info[kCGWindowNumber as String] as? CGWindowID) == window
        }
        return false
    }

    /// The app's front window without taking a picture: all a cell-pointing request needs.
    func locate(_ app: ForegroundApp?) throws -> CapturedScreen {
        guard let app else { throw ScreenCaptureError(message: Self.noApp) }
        guard let (windowID, frame) = Self.frontWindow(of: app.pid) else {
            throw ScreenCaptureError(message: "\(app.name) has no visible window to share. Bring it into view and ask again.")
        }
        return CapturedScreen(jpeg: Data(), windowID: windowID, frame: frame, app: app)
    }

    static let noApp = "No app is selected for screen sharing yet. Click the app you want help with once, then return to Pip."

    func capture(_ app: ForegroundApp?) async throws -> CapturedScreen {
        guard let app else { throw ScreenCaptureError(message: Self.noApp) }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ScreenCaptureError(message: "Allow F2L under System Settings › Privacy & Security › Screen Recording, then reopen F2L.")
        }
        guard let (windowID, frame) = Self.frontWindow(of: app.pid) else {
            throw ScreenCaptureError(message: "\(app.name) has no visible window to share. Bring it into view and ask again.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError(message: "\(app.name)'s window changed while F2L was looking. Ask again.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let pixelScale = max(1, Double(filter.pointPixelScale))
        let scale = min(1, Self.maxImageSide / (Double(max(frame.width, frame.height)) * pixelScale)) * pixelScale
        config.width = max(1, Int(Double(frame.width) * scale))
        config.height = max(1, Int(Double(frame.height) * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenCaptureError(message: "macOS didn't allow a picture of \(app.name) just now. Check Screen Recording permission for F2L.")
        }
        guard let jpeg = Self.jpegData(image) else { throw ScreenCaptureError(message: "F2L couldn't encode the screen image.") }
        return CapturedScreen(jpeg: jpeg, windowID: windowID, frame: frame, app: app)
    }

    nonisolated static func jpegData(_ image: CGImage, quality: Double = 0.82) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
