import AppKit
import SwiftUI

/// The small bar at the top of the screen (in the notch on MacBooks). Never takes keyboard focus,
/// so the learner's app stays in front and keeps its Accessibility focus.
@MainActor
final class IslandController {
    static let collapsedSize = CGSize(width: 260, height: 38)
    static let expandedSize = CGSize(width: 440, height: 250)

    private let panel: NSPanel
    private let model: IslandModel

    init(model: IslandModel, actions: IslandActions) {
        self.model = model
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        let host = IslandHostingView(rootView: IslandView(model: model, actions: actions))
        host.onHover = { [weak self] inside in self?.setExpanded(inside) }
        panel.contentView = host
        layout(expanded: false, animate: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layout(expanded: self?.model.expanded ?? false, animate: false) }
        }
    }

    /// Opens the bar and puts the cursor in the text box (menu-bar "Type a question…").
    func focusInput() {
        setExpanded(true)
        panel.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    func setExpanded(_ expanded: Bool) {
        // Don't fold away while the learner is typing.
        if !expanded, model.inputActive { return }
        guard expanded != model.expanded else { return }
        model.expanded = expanded
        layout(expanded: expanded, animate: true)
    }

    private func layout(expanded: Bool, animate: Bool) {
        guard let screen = NSScreen.screens.first else { return }
        // On notched MacBooks the camera housing hides the middle of the bar: grow the bar so the orb sits
        // to the left of the notch and the phase word to its right.
        var notch: CGFloat = 0
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = max(0, screen.frame.width - left.width - right.width)
        }
        model.notchWidth = notch
        var size = expanded ? Self.expandedSize : Self.collapsedSize
        if notch > 0 { size.width = max(size.width, notch + 2 * 120) }
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: animate)
    }
}

private final class IslandPanel: NSPanel {
    // Key-capable so the text box can take typing; it's non-activating, so the learner's app stays in front.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Beacon is never the active app, so hover and first clicks must work in an inactive window:
/// an always-active tracking area for hover, and first-mouse so a press on the orb isn't swallowed.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

struct IslandActions {
    var pressTalk: () -> Void
    var releaseTalk: () -> Void
    var togglePause: () -> Void
    var clearPointer: () -> Void
    var submitText: (String) -> Void
    var newConversation: () -> Void
    var openSettings: () -> Void
    var openOnboarding: () -> Void
    var saveSnapshot: () -> Void
    var quit: () -> Void
}

private struct IslandView: View {
    @ObservedObject var model: IslandModel
    let actions: IslandActions

    @State private var holding = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Orb(phase: model.phase, paused: model.paused, level: model.micLevel)
                    .frame(width: 24, height: 24)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !holding { holding = true; actions.pressTalk() } }
                            .onEnded { _ in holding = false; actions.releaseTalk() }
                    )
                    .help("Press and hold to talk")
                if model.notchWidth > 0 {
                    // Nothing can be seen behind the camera housing: short words either side of it.
                    Text("Beacon").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: model.notchWidth)
                    Text(phaseWord).font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(model.hasError ? Color.orange : Color.white.opacity(0.9))
                } else {
                    statusText
                    Spacer(minLength: 0)
                }
            }
            if model.expanded {
                if model.notchWidth > 0 { statusText }
                expandedContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18).fill(Color.black))
    }

    private func sendDraft() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft = ""
        inputFocused = false
        actions.submitText(text)
    }

    private var statusText: some View {
        Text(model.status)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(model.hasError ? Color.orange : Color.white.opacity(0.9))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var phaseWord: String {
        if model.hasError { return "Needs help" }
        if model.paused { return "Paused" }
        return switch model.phase {
        case .idle: "Ready"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.heard.isEmpty {
                Text("You: \(model.heard)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            if model.phase == .listening {
                ProgressView(value: model.micLevel)
                    .tint(model.micLevel < 0.15 ? .orange : .green)
                    .controlSize(.small)
            }
            ScrollView {
                Text(model.reply.isEmpty ? "Ask me anything about using AI tools. I'll circle where to click." : model.reply)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 70)
            HStack(spacing: 6) {
                TextField("Or type your question…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .focused($inputFocused)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(draft.isEmpty ? .gray : Color.orange)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onChange(of: inputFocused) { _, focused in model.inputActive = focused || !draft.isEmpty }
            .onChange(of: draft) { _, text in model.inputActive = inputFocused || !text.isEmpty }
            .onChange(of: model.focusRequest) { _, _ in inputFocused = true }
            HStack(spacing: 8) {
                IslandButton(title: model.paused ? "Resume" : "Pause", systemImage: model.paused ? "eye" : "eye.slash", action: actions.togglePause)
                IslandButton(title: "Clear circle", systemImage: "circle.slash", action: actions.clearPointer)
                IslandButton(title: "Start over", systemImage: "arrow.counterclockwise", action: actions.newConversation)
                Spacer()
                if !model.latency.isEmpty {
                    Text(model.latency).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                }
                Menu {
                    Button("Settings…", action: actions.openSettings)
                    Button("Privacy & permissions…", action: actions.openOnboarding)
                    if Preferences.developerMode {
                        Divider()
                        Button("Save spike snapshot (developer)", action: actions.saveSnapshot)
                    }
                    Divider()
                    Button("Quit Beacon", action: actions.quit)
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.white.opacity(0.8))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

private struct IslandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Beacon's character: a small glowing light that breathes while idle, ripples while listening,
/// spins while thinking, and pulses while speaking.
struct Orb: View {
    let phase: CoachPhase
    let paused: Bool
    /// Microphone loudness 0...1; makes the orb swell with your voice while listening.
    var level: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [core, glow.opacity(0.0)], center: .center, startRadius: 1, endRadius: 14))
                    .scaleEffect(1 + amplitude * sin(t * speed) + (phase == .listening ? level * 0.5 : 0))
                Circle()
                    .fill(RadialGradient(colors: [.white, core], center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 8))
                    .frame(width: 13, height: 13)
                if phase == .thinking {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(glow, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 21, height: 21)
                        .rotationEffect(.radians(t * 5))
                }
                if phase == .listening {
                    Circle()
                        .stroke(glow.opacity(0.7 - (t * 1.5).truncatingRemainder(dividingBy: 1) * 0.7), lineWidth: 1.5)
                        .scaleEffect(0.6 + (t * 1.5).truncatingRemainder(dividingBy: 1) * 0.6)
                }
            }
        }
        .opacity(paused ? 0.4 : 1)
        .contentShape(Circle())
    }

    private var core: Color {
        if paused { return .gray }
        return switch phase {
        case .idle: Color(red: 1.0, green: 0.7, blue: 0.25)
        case .listening: Color(red: 0.35, green: 0.85, blue: 0.55)
        case .thinking: Color(red: 0.55, green: 0.65, blue: 1.0)
        case .speaking: Color(red: 1.0, green: 0.62, blue: 0.0)
        }
    }

    private var glow: Color { core }

    private var amplitude: Double {
        switch phase {
        case .idle: 0.06
        case .listening: 0.12
        case .thinking: 0.04
        case .speaking: 0.18
        }
    }

    private var speed: Double {
        switch phase {
        case .idle: 1.6
        case .listening: 5
        case .thinking: 3
        case .speaking: 9
        }
    }
}
