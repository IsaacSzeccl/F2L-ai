import CoreGraphics
import Foundation

/// One saved test case for the model spike: a real screen snapshot, a learner question, and the
/// control a correct answer should point at. Written by the app's "Save spike snapshot" debug action.
public struct SpikeCase: Codable, Sendable {
    public var name: String
    public var question: String
    public var context: ScreenContext
    /// The element id a correct answer points at. Fill this in by hand after saving the snapshot.
    public var expectedElementID: String?

    public init(name: String, question: String, context: ScreenContext, expectedElementID: String? = nil) {
        self.name = name
        self.question = question
        self.context = context
        self.expectedElementID = expectedElementID
    }
}

public struct SpikeResult: Sendable {
    public var name: String
    public var timeToFirstEvent: TimeInterval?
    public var total: TimeInterval
    public var pointedAt: PointerCommand?
    /// The model's pointer resolved to something drawable (valid id or valid box).
    public var validPointer: Bool
    /// Pointed at the expected element (nil when the case has no expectation).
    public var hit: Bool?
    public var spokenText: String
    public var error: String?

    public init(name: String, timeToFirstEvent: TimeInterval?, total: TimeInterval, pointedAt: PointerCommand?,
                validPointer: Bool, hit: Bool?, spokenText: String, error: String?) {
        self.name = name
        self.timeToFirstEvent = timeToFirstEvent
        self.total = total
        self.pointedAt = pointedAt
        self.validPointer = validPointer
        self.hit = hit
        self.spokenText = spokenText
        self.error = error
    }
}

public enum SpikeScoring {
    /// Scores a model's pointer command against a case.
    public static func score(_ command: PointerCommand?, for spikeCase: SpikeCase) -> (valid: Bool, hit: Bool?) {
        guard let command else { return (false, spikeCase.expectedElementID == nil ? nil : false) }
        let annotation = CoachTools.resolve(command, in: spikeCase.context)
        guard let expected = spikeCase.expectedElementID,
              let target = spikeCase.context.element(withID: expected) else {
            return (annotation != nil, nil)
        }
        switch command {
        case let .element(id, _):
            return (annotation != nil, id == expected)
        case .region:
            // A region counts as a hit only if it contains the target's centre and isn't huge.
            guard let rect = annotation?.rect else { return (false, false) }
            let centre = CGPoint(x: target.frame.midX, y: target.frame.midY)
            let tightEnough = rect.width * rect.height <= max(target.frame.width * target.frame.height * 9, 120 * 120)
            return (true, rect.contains(centre) && tightEnough)
        case .clear:
            return (false, false)
        }
    }
}
