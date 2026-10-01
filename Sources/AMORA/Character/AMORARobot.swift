import Foundation
import SwiftUI
import Observation
import QuartzCore

@Observable @MainActor
final class AMORARobot {
    static let shared = AMORARobot()

    var expression: Expression = .idle()
    var state: AMORAState = .idle
    var isHovering: Bool = false
    var eyeDirection: CGPoint = .zero
    var targetEyeDirection: CGPoint = .zero
    var breathingPhase: Double = 0
    var blinkPhase: Double = 0
    var headMovementPhase: Double = 0
    var antennaPhase: Double = 0

    private var animationTimer: Timer?
    private var lastBlink: Date = Date()
    private var nextBlinkInterval: TimeInterval = 3.5

    init() {
        startAnimations()
    }

    func stopAnimations() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startAnimations() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFrame()
            }
        }
    }

    private func updateFrame() {
        let elapsed = CACurrentMediaTime()

        // Smooth breathing motion
        breathingPhase = sin(elapsed * 1.8) * 0.5 + 0.5

        // Antenna subtle vibration / pulse
        antennaPhase = sin(elapsed * 3.0) * 0.5 + 0.5

        // Idle head tilt
        headMovementPhase = sin(elapsed * 0.6) * 0.15

        // Smooth eye following interpolation
        let damping: CGFloat = 0.2
        eyeDirection = CGPoint(
            x: eyeDirection.x + (targetEyeDirection.x - eyeDirection.x) * damping,
            y: eyeDirection.y + (targetEyeDirection.y - eyeDirection.y) * damping
        )

        // Natural blinking logic
        let now = Date()
        let timeSinceBlink = now.timeIntervalSince(lastBlink)
        if timeSinceBlink > nextBlinkInterval {
            lastBlink = now
            nextBlinkInterval = Double.random(in: 2.5...5.5)
            withAnimation(.easeInOut(duration: 0.12)) {
                blinkPhase = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                withAnimation(.easeInOut(duration: 0.12)) {
                    self?.blinkPhase = 0.0
                }
            }
        }
    }

    func updateExpression(for newState: AMORAState) {
        let newExpression: Expression
        switch newState {
        case .idle:
            newExpression = .idle()
        case .watching:
            newExpression = Expression(
                eyes: .normal,
                eyeOffset: .zero,
                mouth: .neutral,
                blinkProgress: 0,
                headTilt: 0,
                antennaPulse: 0.3
            )
        case .hover:
            newExpression = .happy()
        case .thinking:
            newExpression = .thinking()
        case .happy:
            newExpression = .happy()
        case .sleepy:
            newExpression = .sleepy()
        case .alert:
            newExpression = .alert()
        case .music:
            newExpression = .music()
        case .speaking:
            newExpression = Expression(
                eyes: .normal,
                eyeOffset: .zero,
                mouth: .open,
                blinkProgress: 0,
                headTilt: 0,
                antennaPulse: 0.6
            )
        case .error:
            newExpression = .sad()
        case .expanded:
            newExpression = .happy()
        }

        self.expression = newExpression
        self.state = newState
    }

    func setEyeDirection(x: Double, y: Double) {
        let maxOffset: CGFloat = 3.5
        targetEyeDirection = CGPoint(
            x: CGFloat(x) * maxOffset,
            y: CGFloat(y) * maxOffset
        )
    }
}
