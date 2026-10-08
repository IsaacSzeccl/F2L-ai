import AppKit
import CoreText
import os

enum Log {
    static let subsystem = "ai.f2l.companion"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let voice = Logger(subsystem: subsystem, category: "voice")
    static let screen = Logger(subsystem: subsystem, category: "screen")
}

/// Colours copied from the Windows XAML so both companions look the same.
enum Palette {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
    static let ink = hex(0x242529)
    static let panel = hex(0xFEFEFF)
    static let panelBorder = hex(0xE2E3E9)
    static let headerLine = hex(0xEEEFF2)
    static let button = hex(0xF3F4F6)
    static let send = hex(0x303138)
    static let composer = hex(0xF7F7F9)
    static let composerBorder = hex(0xE6E7EB)
    static let userBubble = hex(0xF1F2F5)
    static let lavender = hex(0xF0EEF7)
    static let lavenderInk = hex(0x706581)
    static let selection = hex(0xCDC6F2)
    static let verified = hex(0x378D74)
    static let approximate = hex(0xC18E38)
}

/// Inter is bundled under the SIL Open Font License (Assets/Fonts/LICENSE.txt), as on Windows.
enum Fonts {
    static func register() {
        guard let fonts = Assets.url("Fonts") else { return }
        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold"] {
            CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent("\(name).ttf") as CFURL, .process, nil)
        }
    }

    static func inter(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let name = switch weight {
        case .semibold, .bold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

/// Finds the shared artwork. Inside F2L.app it is Contents/Resources/Assets; when run from the
/// repository it is the Windows project's Assets folder, so both apps use the same files.
enum Assets {
    static let root: URL? = {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Assets"),
           fm.fileExists(atPath: bundled.appendingPathComponent("Pip/frames.json").path) { return bundled }
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("Windows/F2L.Windows/Assets")
            if fm.fileExists(atPath: candidate.appendingPathComponent("Pip/frames.json").path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }()

    static func url(_ relative: String) -> URL? { root?.appendingPathComponent(relative) }
}

/// AppKit uses bottom-left screen coordinates; capture, placement and the shared logic use top-left.
enum ScreenSpace {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAppKit(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toTopLeft(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static var cursor: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// The visible (menu bar and Dock excluded) area of the screen under `point`, top-left coordinates.
    static func workArea(at point: CGPoint) -> CGRect {
        let flipped = NSPoint(x: point.x, y: primaryHeight - point.y)
        let screen = NSScreen.screens.first { NSMouseInRect(flipped, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        return toTopLeft(screen.visibleFrame)
    }
}
