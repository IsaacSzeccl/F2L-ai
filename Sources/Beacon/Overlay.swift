import AppKit
import CoachCore
import SwiftUI

/// Draws the coach's circle directly on top of the learner's real windows. One transparent,
/// click-through window per display, so the learner clicks straight through the annotation.
@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private var windows: [NSWindow] = []
    private var screenObserver: Any?

    init() {
        rebuildWindows()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }
    }

    var current: Annotation? { model.annotation }

    func show(_ annotation: Annotation) {
        model.annotation = annotation
        model.version += 1
    }

    func move(to rect: CGRect) {
        guard var annotation = model.annotation else { return }
        annotation.rect = rect
        model.annotation = annotation
    }

    func clear() {
        model.annotation = nil
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: OverlayView(model: model, screenFrame: screen.topLeftFrame))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var annotation: Annotation?
    @Published var version = 0
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    let screenFrame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let annotation = model.annotation, screenFrame.intersects(annotation.rect) {
                let local = annotation.rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
                AnnotationMark(annotation: annotation, localRect: local, screenSize: screenFrame.size)
                    .id(model.version)
                    .transition(.opacity)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .animation(.easeOut(duration: 0.2), value: model.annotation)
    }
}

private struct AnnotationMark: View {
    let annotation: Annotation
    let localRect: CGRect
    let screenSize: CGSize

    @State private var appeared = false
    @State private var pulse = false

    private static let accent = Color(red: 1.0, green: 0.62, blue: 0.0)

    var body: some View {
        let ring = annotation.style == .precise
            ? Geometry.ringRect(for: localRect)
            : Geometry.ringRect(for: localRect, padding: 18, minSide: 90)
        ZStack(alignment: .topLeading) {
            ringShape(ring)
            if annotation.style == .precise {
                Arrow(target: ring, screenSize: screenSize)
                    .stroke(Self.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .opacity(appeared ? 1 : 0)
            }
            if let caption = annotation.caption {
                CaptionBubble(text: caption, approximate: annotation.style == .approximate)
                    .position(captionPosition(for: ring))
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    @ViewBuilder
    private func ringShape(_ ring: CGRect) -> some View {
        let scale = appeared ? (pulse ? 1.06 : 1.0) : 1.6
        if annotation.style == .precise {
            RoundedRectangle(cornerRadius: min(ring.height, ring.width) / 2.4)
                .stroke(Self.accent, lineWidth: 4)
                .background(RoundedRectangle(cornerRadius: min(ring.height, ring.width) / 2.4).fill(Self.accent.opacity(0.10)))
                .shadow(color: Self.accent.opacity(0.8), radius: pulse ? 12 : 4)
                .frame(width: ring.width, height: ring.height)
                .scaleEffect(scale)
                .position(x: ring.midX, y: ring.midY)
        } else {
            Ellipse()
                .stroke(Self.accent, style: StrokeStyle(lineWidth: 4, dash: [10, 8]))
                .background(Ellipse().fill(Self.accent.opacity(0.08)))
                .frame(width: ring.width, height: ring.height)
                .scaleEffect(scale)
                .position(x: ring.midX, y: ring.midY)
        }
    }

    private func captionPosition(for ring: CGRect) -> CGPoint {
        let below = CGPoint(x: ring.midX, y: ring.maxY + 26)
        return below.y + 30 < screenSize.height ? below : CGPoint(x: ring.midX, y: ring.minY - 26)
    }
}

/// A short arrow pointing at the ring from whichever side has room.
private struct Arrow: Shape {
    let target: CGRect
    let screenSize: CGSize

    func path(in _: CGRect) -> Path {
        let fromLeft = target.minX > 140
        let fromTop = target.minY > 140
        let tip = CGPoint(x: fromLeft ? target.minX - 6 : target.maxX + 6, y: fromTop ? target.minY - 6 : target.maxY + 6)
        let length: CGFloat = 70
        let tail = CGPoint(x: tip.x + (fromLeft ? -length : length), y: tip.y + (fromTop ? -length : length))
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let head: CGFloat = 16
        var path = Path()
        path.move(to: tail)
        path.addLine(to: tip)
        path.move(to: CGPoint(x: tip.x - head * cos(angle - .pi / 6), y: tip.y - head * sin(angle - .pi / 6)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - head * cos(angle + .pi / 6), y: tip.y - head * sin(angle + .pi / 6)))
        return path
    }
}

private struct CaptionBubble: View {
    let text: String
    let approximate: Bool

    var body: some View {
        Text(approximate && text != "Around here" ? "\(text), roughly here" : text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(red: 1.0, green: 0.78, blue: 0.35)))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .fixedSize()
    }
}
