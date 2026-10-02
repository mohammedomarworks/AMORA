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
    /// One-shot celebratory bounce amplitude (0 at rest). Views read this to pop
    /// AMORA on happy moments like a finished focus session.
    var bouncePhase: Double = 0

    private var animationTimer: Timer?
    private var lastBlink: Date = Date()
    private var nextBlinkInterval: TimeInterval = 3.5

    // Idle-life bookkeeping. All of this stays calm: cooldowns gate every behavior
    // so AMORA mostly rests, with the occasional glance or slow blink.
    private var lastInteraction: Date = Date()
    private var lastCursorMove: Date = .distantPast
    private var lastGazeShift: Date = Date()
    private var nextGazeInterval: TimeInterval = 5.0
    private var isAsleep = false

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
        let motion = AppState.shared.settings.motionScale   // 0 when Reduce Motion is on

        // Ambient life — breathing, antenna shimmer, head sway — scales with the
        // user's intensity preference and collapses to stillness under Reduce Motion.
        breathingPhase = 0.5 + sin(elapsed * 1.8) * 0.5 * motion
        antennaPhase = 0.5 + sin(elapsed * 3.0) * 0.5 * motion
        headMovementPhase = sin(elapsed * 0.6) * 0.15 * motion

        // Bounce decays back to rest after a celebration pops it.
        if bouncePhase > 0.0001 {
            bouncePhase *= 0.85
            if bouncePhase < 0.0001 { bouncePhase = 0 }
        }

        // Smooth eye follow toward the current target.
        let damping: CGFloat = 0.2
        eyeDirection = CGPoint(
            x: eyeDirection.x + (targetEyeDirection.x - eyeDirection.x) * damping,
            y: eyeDirection.y + (targetEyeDirection.y - eyeDirection.y) * damping
        )

        updateIdleLife(now: Date(), motion: motion)
        updateBlink(now: Date())
    }

    /// Occasional, cooldown-gated glances when the cursor is quiet, plus drifting
    /// off to sleep after a long idle stretch. Mostly this does nothing — that's
    /// the point.
    private func updateIdleLife(now: Date, motion: Double) {
        let settings = AppState.shared.settings
        let state = AppState.shared.stateManager.currentState
        let restful = (state == .idle || state == .watching || state == .sleepy)

        // Fall asleep after the idle timeout; wake on the next interaction.
        if settings.sleepMode, restful, !isAsleep,
           now.timeIntervalSince(lastInteraction) > settings.idleTimeout {
            isAsleep = true
            AppState.shared.stateManager.transition(to: .sleepy)
            updateExpression(for: .sleepy)
        }

        guard motion > 0, restful, !isAsleep else { return }

        // Idle gaze wander only when the cursor itself isn't driving the eyes.
        if now.timeIntervalSince(lastCursorMove) > 2.5,
           now.timeIntervalSince(lastGazeShift) > nextGazeInterval {
            lastGazeShift = now
            nextGazeInterval = Double.random(in: 3.5...7.5)
            // Bias toward center so AMORA keeps returning to a neutral gaze.
            if Bool.random() {
                targetEyeDirection = .zero
            } else {
                targetEyeDirection = CGPoint(
                    x: CGFloat.random(in: -2.5...2.5),
                    y: CGFloat.random(in: -1.5...2.5)
                )
            }
        }
    }

    /// Natural blinking with varied timing. A small fraction of blinks become a
    /// slow blink or a quick double blink so it never looks metronomic.
    private func updateBlink(now: Date) {
        guard now.timeIntervalSince(lastBlink) > nextBlinkInterval else { return }
        lastBlink = now
        nextBlinkInterval = Double.random(in: 2.5...5.5)

        let roll = Double.random(in: 0...1)
        if roll < 0.1 {
            blinkOnce(duration: 0.28)                       // slow, sleepy blink
        } else if roll < 0.2 {
            blinkOnce(duration: 0.1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                self?.blinkOnce(duration: 0.1)              // double blink
            }
        } else {
            blinkOnce(duration: 0.12)
        }
    }

    private func blinkOnce(duration: Double) {
        withAnimation(.easeInOut(duration: duration)) { blinkPhase = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            withAnimation(.easeInOut(duration: duration)) { self?.blinkPhase = 0.0 }
        }
    }

    /// Pops a short celebratory bounce (decays in `updateFrame`).
    func playBounce() {
        guard AppState.shared.settings.motionScale > 0 else { return }
        bouncePhase = 1.0
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
        case .focused:
            newExpression = .thinking()
        case .happy:
            newExpression = .happy()
        case .curious:
            newExpression = .curious()
        case .excited:
            newExpression = .excited()
        case .concerned:
            newExpression = .concerned()
        case .surprised:
            newExpression = .surprised()
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
        case .aiThinking:
            newExpression = .thinking()
        case .aiResponse:
            newExpression = .happy()
        case .aiError:
            newExpression = .concerned()
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
        lastCursorMove = Date()
        noteInteraction()
    }

    /// Record any sign of life from the user: resets the idle clock and gently
    /// wakes AMORA if it had drifted off to sleep.
    func noteInteraction() {
        lastInteraction = Date()
        if isAsleep {
            isAsleep = false
            if AppState.shared.stateManager.currentState == .sleepy {
                AppState.shared.stateManager.resetToIdle()
                updateExpression(for: .idle)
            }
        }
    }
}
