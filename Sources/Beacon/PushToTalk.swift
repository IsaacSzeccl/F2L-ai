import AppKit

/// Hold the RIGHT Option key to talk, from any app. Pressing another key while holding it cancels
/// (so typing ⌥-accents never triggers the coach). The island's orb offers the same press-and-hold.
@MainActor
final class PushToTalk {
    var onPress: (() -> Void)?
    var onRelease: ((_ cancelled: Bool) -> Void)?

    private static let rightOptionKeyCode: UInt16 = 61
    private var monitors: [Any] = []
    private var holding = false
    private var cancelled = false

    func start() {
        stop()
        let flags: (NSEvent) -> Void = { [weak self] event in self?.handleFlags(event) }
        let keyDown: (NSEvent) -> Void = { [weak self] _ in
            guard let self, self.holding else { return }
            self.cancelled = true
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyDown) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keyDown($0); return $0 }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == Self.rightOptionKeyCode else { return }
        // The device-specific right-Option bit (NX_DEVICERALTKEYMASK), so holding left Option can't mask the release.
        let down = event.modifierFlags.rawValue & 0x40 != 0
        if down, !holding {
            holding = true
            cancelled = false
            onPress?()
        } else if !down, holding {
            holding = false
            onRelease?(cancelled)
        }
    }
}
