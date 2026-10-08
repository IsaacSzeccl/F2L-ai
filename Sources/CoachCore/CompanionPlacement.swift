import CoreGraphics

public enum PointingDirection: Sendable { case none, left, right, up, down }

/// WPF's Rect.IntersectsWith and Rect.Contains(Point) include the edges; CGRect's versions don't.
/// Placement uses the WPF rules so both companions accept and reject exactly the same spots.
extension CGRect {
    public func touches(_ other: CGRect) -> Bool {
        !isNull && !other.isNull && other.minX <= maxX && other.maxX >= minX && other.minY <= maxY && other.maxY >= minY
    }

    public func containsIncludingEdges(_ point: CGPoint) -> Bool {
        !isNull && point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

public struct CompanionSpot: Equatable, Sendable {
    public var bounds: CGRect
    public var direction: PointingDirection
}

/// Where Pip stands while teaching. Rects are global, top-left origin; `scale` converts design units
/// to the caller's units (1 for Mac points, DPI/96 for Windows pixels). Mirrors CompanionPlacement.cs.
public enum CompanionPlacement {
    public static func protectedArea(_ target: CGRect, scale: CGFloat) -> CGRect {
        target.insetBy(dx: -30 * scale, dy: -24 * scale)
    }

    public static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isEmpty && rect.origin.x.isFinite && rect.origin.y.isFinite &&
            rect.width.isFinite && rect.height.isFinite && rect.width >= 2 && rect.height >= 2
    }

    public static func choose(target: CGRect, work: CGRect, size: CGSize, panel: CGRect?, cursor: CGPoint,
                              scale: CGFloat, previous: CGRect? = nil) -> CompanionSpot? {
        guard isUsable(target), size.width > 0, size.height > 0 else { return nil }
        let safe = protectedArea(target, scale: scale)
        let gap = 12 * scale
        let center = CGPoint(x: target.midX, y: target.midY)
        var candidates: [CompanionSpot] = []
        func add(_ x: CGFloat, _ y: CGFloat, _ direction: PointingDirection) {
            let bounds = CGRect(x: x, y: y, width: size.width, height: size.height)
            guard work.contains(bounds), !bounds.touches(safe), !(panel.map { bounds.touches($0) } ?? false) else { return }
            candidates.append(CompanionSpot(bounds: bounds, direction: direction))
        }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, work.minY), max(work.minY, work.maxY - size.height)) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, work.minX), max(work.minX, work.maxX - size.width)) }
        // Favour a side so the learner can continue working along the current row.
        for y in [center.y - size.height / 2, safe.minY, safe.maxY - size.height] {
            add(safe.maxX + gap, clampY(y), .left)
            add(safe.minX - gap - size.width, clampY(y), .right)
        }
        for x in [center.x - size.width / 2, safe.minX, safe.maxX - size.width] {
            add(clampX(x), safe.maxY + gap, .up)
            add(clampX(x), safe.minY - gap - size.height, .down)
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        func score(_ spot: CompanionSpot) -> CGFloat {
            var score = distance(CGPoint(x: spot.bounds.midX, y: spot.bounds.midY), center)
            if spot.bounds.insetBy(dx: -40 * scale, dy: -40 * scale).containsIncludingEdges(cursor) { score += 300 * scale }
            if let previous { score += distance(spot.bounds.origin, previous.origin) * 0.35 }
            if spot.direction == .up || spot.direction == .down { score += 25 * scale }
            return score
        }
        // Stable: equal scores keep candidate order, like LINQ OrderBy.
        return candidates.enumerated().min { (score($0.element), $0.offset) < (score($1.element), $1.offset) }?.element
    }

    public static func shouldYield(sprite: CGRect, protectedTarget: CGRect, cursor: CGPoint, caret: CGRect?, scale: CGFloat) -> Bool {
        if sprite.insetBy(dx: -28 * scale, dy: -28 * scale).containsIncludingEdges(cursor) || sprite.touches(protectedTarget) { return true }
        guard let caret, !caret.isNull else { return false }
        return sprite.touches(caret.insetBy(dx: -40 * scale, dy: -24 * scale))
    }

    /// Converts a model target in thousandths of the screenshot to global coordinates of the captured window.
    public static func fromScreenshot(window: CGRect, target: ScreenTarget) -> CGRect {
        CGRect(x: window.minX + CGFloat(target.left) * window.width / 1000,
               y: window.minY + CGFloat(target.top) * window.height / 1000,
               width: CGFloat(target.right - target.left) * window.width / 1000,
               height: CGFloat(target.bottom - target.top) * window.height / 1000)
    }
}

/// Which painted pose Pip shows. Frame numbers index the 16 poses in expressions.png / directions.png.
/// Timings mirror Windows/F2L.Windows/PipView.xaml.cs exactly.
public struct PipPose: Equatable, Sendable {
    public var directions: Bool
    public var frame: Int
    public var mirrored: Bool

    public struct State: Sendable {
        public var intent: QuestionIntent = .quickFact
        public var pointing: PointingDirection = .none
        public var travelling: PointingDirection = .none
        public var speaking = false, listening = false, thinking = false, reducedMotion = false
        /// The warm smile and wave used for greetings and correct answers.
        public var waving = false
        public init() {}
    }

    public static func at(milliseconds: Int, _ s: State) -> PipPose {
        let time = s.reducedMotion ? 0 : milliseconds % 1_000_000
        if s.travelling != .none && !s.reducedMotion {
            let vertical = s.travelling == .up || s.travelling == .down
            return PipPose(directions: true, frame: vertical ? 12 + time / 250 % 2 : 10 + time / 170 % 2, mirrored: s.travelling == .left)
        }
        if s.pointing != .none {
            var frame = switch s.pointing { case .left: 0; case .right: 2; case .up: 4; default: 6 }
            // The alternate up frame lowers the arm, so hold the verified upward pose.
            if s.speaking && !s.reducedMotion && s.pointing != .up { frame += time / 200 % 2 }
            return PipPose(directions: true, frame: frame, mirrored: false)
        }
        let frame: Int
        if s.waving { frame = s.reducedMotion ? 14 : sequence(time, [14, 15], [420, 420]) }
        else if s.listening { frame = sequence(time, [8, 9, 10, 11], [1100, 800, 120, 1400]) }
        else if s.thinking { frame = sequence(time, [4, 5, 6, 7], [1000, 800, 120, 800]) }
        else if s.speaking && !s.reducedMotion { frame = sequence(time, [2, 3, 2, 0], [180, 140, 180, 140]) }
        else {
            frame = switch s.intent {
            case .multiPart: sequence(time, [4, 5, 6, 7], [1600, 1000, 120, 1000])
            case .clarificationNeeded: sequence(time, [8, 9, 10, 11], [1800, 900, 120, 1200])
            case .procedural: sequence(time, [12, 13], [3600, 650])
            case .quickFact: sequence(time, [0, 1], [3900, 130])
            }
        }
        return PipPose(directions: false, frame: frame, mirrored: false)
    }

    private static func sequence(_ time: Int, _ frames: [Int], _ durations: [Int]) -> Int {
        var t = time % durations.reduce(0, +)
        for (frame, duration) in zip(frames, durations) {
            if t < duration { return frame }
            t -= duration
        }
        return frames[0]
    }
}
