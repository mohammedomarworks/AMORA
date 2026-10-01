import Foundation

struct Expression: Equatable {
    let eyes: EyeShape
    let eyeOffset: CGPoint
    let mouth: MouthShape
    let blinkProgress: Double
    let headTilt: Double
    let antennaPulse: Double

    static let neutral = Expression(
        eyes: .normal,
        eyeOffset: .zero,
        mouth: .neutral,
        blinkProgress: 0,
        headTilt: 0,
        antennaPulse: 0
    )

    static func idle() -> Expression {
        Expression(
            eyes: .normal,
            eyeOffset: .zero,
            mouth: .neutral,
            blinkProgress: 0,
            headTilt: 0,
            antennaPulse: 0
        )
    }

    static func happy() -> Expression {
        Expression(
            eyes: .happy,
            eyeOffset: .zero,
            mouth: .smile,
            blinkProgress: 0,
            headTilt: 0,
            antennaPulse: 0
        )
    }

    static func thinking() -> Expression {
        Expression(
            eyes: .narrow,
            eyeOffset: CGPoint(x: 0, y: -2),
            mouth: .neutral,
            blinkProgress: 0,
            headTilt: 0.2,
            antennaPulse: 0.5
        )
    }

    static func sad() -> Expression {
        Expression(
            eyes: .sad,
            eyeOffset: .zero,
            mouth: .sad,
            blinkProgress: 0,
            headTilt: -0.1,
            antennaPulse: 0
        )
    }

    static func surprised() -> Expression {
        Expression(
            eyes: .wide,
            eyeOffset: .zero,
            mouth: .open,
            blinkProgress: 0,
            headTilt: 0,
            antennaPulse: 0.8
        )
    }

    /// Head cocked, eyes glancing up — "huh, what's this?"
    static func curious() -> Expression {
        Expression(
            eyes: .normal,
            eyeOffset: CGPoint(x: 1.5, y: 2),
            mouth: .neutral,
            blinkProgress: 0,
            headTilt: 0.28,
            antennaPulse: 0.5
        )
    }

    /// Soft downward eyes — gentle worry, never alarming.
    static func concerned() -> Expression {
        Expression(
            eyes: .sad,
            eyeOffset: .zero,
            mouth: .neutral,
            blinkProgress: 0.1,
            headTilt: -0.12,
            antennaPulse: 0.3
        )
    }

    /// Big grin + lively antenna — celebratory, paired with a small bounce.
    static func excited() -> Expression {
        Expression(
            eyes: .happy,
            eyeOffset: .zero,
            mouth: .smile,
            blinkProgress: 0,
            headTilt: 0,
            antennaPulse: 1.0
        )
    }

    static func sleepy() -> Expression {
        Expression(
            eyes: .halfClosed,
            eyeOffset: .zero,
            mouth: .neutral,
            blinkProgress: 0.3,
            headTilt: -0.15,
            antennaPulse: 0.2
        )
    }

    static func alert() -> Expression {
        Expression(
            eyes: .wide,
            eyeOffset: CGPoint(x: 0, y: 0),
            mouth: .neutral,
            blinkProgress: 0,
            headTilt: 0,
            antennaPulse: 1.0
        )
    }

    static func music() -> Expression {
        Expression(
            eyes: .happy,
            eyeOffset: CGPoint(x: 0, y: 0),
            mouth: .smile,
            blinkProgress: 0,
            headTilt: 0,
            antennaPulse: 0.3
        )
    }

    enum EyeShape: String, CaseIterable {
        case normal, happy, sad, wide, narrow, halfClosed
    }

    enum MouthShape: String, CaseIterable {
        case neutral, smile, open, sad
    }

    func interpolated(to: Expression, fraction: Double) -> Expression {
        let clamp = max(0, min(1, fraction))
        return Expression(
            eyes: clamp < 0.5 ? eyes : to.eyes,
            eyeOffset: CGPoint(
                x: eyeOffset.x + (to.eyeOffset.x - eyeOffset.x) * clamp,
                y: eyeOffset.y + (to.eyeOffset.y - eyeOffset.y) * clamp
            ),
            mouth: clamp < 0.5 ? mouth : to.mouth,
            blinkProgress: blinkProgress + (to.blinkProgress - blinkProgress) * clamp,
            headTilt: headTilt + (to.headTilt - headTilt) * clamp,
            antennaPulse: antennaPulse + (to.antennaPulse - antennaPulse) * clamp
        )
    }
}
