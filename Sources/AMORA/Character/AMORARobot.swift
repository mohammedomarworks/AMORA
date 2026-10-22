import Foundation
import SwiftUI
import Observation
import QuartzCore

/// Discrete expressive mascot reaction states triggered by user interaction.
enum MascotReaction: String, CaseIterable, Equatable, Sendable {
    case affection
    case excited
    case curious
    case grumpy

    var displayName: String {
        switch self {
        case .affection: return "Affection"
        case .excited: return "Excited"
        case .curious: return "Curious"
        case .grumpy: return "Playfully Grumpy"
        }
    }

    var badgeText: String {
        switch self {
        case .affection: return "Love"
        case .excited: return "Excited"
        case .curious: return "Curious"
        case .grumpy: return "Grumpy"
        }
    }

    var badgeIcon: String {
        switch self {
        case .affection: return "heart.fill"
        case .excited: return "sparkles"
        case .curious: return "eye.fill"
        case .grumpy: return "face.dashed"
        }
    }

    var expressiveMessage: String {
        switch self {
        case .affection: return "Sending positive vibes! ❤️"
        case .excited: return "Energized and ready! ✨"
        case .curious: return "Observing closely! 👀"
        case .grumpy: return "Careful with the visor! 🤖"
        }
    }

    var sound: AMORASound {
        switch self {
        case .affection: return .pop
        case .excited: return .success
        case .curious: return .click
        case .grumpy: return .click
        }
    }

    var expression: Expression {
        switch self {
        case .affection: return .affection()
        case .excited: return .excited()
        case .curious: return .curious()
        case .grumpy: return .grumpy()
        }
    }

    var state: AMORAState {
        switch self {
        case .affection: return .affection
        case .excited: return .excited
        case .curious: return .curious
        case .grumpy: return .grumpy
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .affection: return "feeling affectionate with heart eyes"
        case .excited: return "cheerful and excited"
        case .curious: return "curious and attentive"
        case .grumpy: return "playfully grumpy pouting"
        }
    }
}

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
    /// Transient head wiggle rotation for playful grumpy reactions.
    var wigglePhase: Double = 0

    /// Currently active user click reaction, if any.
    private(set) var activeReaction: MascotReaction?
    private(set) var activeReactionMessage: String?
    private var lastClickTime: Date = .distantPast
    private var rapidClickCount: Int = 0
    private var reactionCycleIndex: Int = 0
    private var reactionRevertToken: Int = 0
    private var previousStateBeforeReaction: AMORAState?

    /// Minimum duration between click interactions to prevent rapid-click animation glitching.
    var clickDebounceThreshold: TimeInterval = 0.22

    private var animationTimer: Timer?
    private var lastBlink: Date = Date()
    private var nextBlinkInterval: TimeInterval = 3.5

    // Idle-life bookkeeping. All of this stays calm: cooldowns gate every behavior
    // so AMORA mostly rests, with the occasional glance or slow blink.
    private var lastInteraction: Date = Date()
    private var lastCursorMove: Date = .distantPast
    private var lastGazeShift: Date = Date()
    private var nextGazeInterval: TimeInterval = 5.0
    private(set) var isAsleep: Bool = false
    private var lastIdleMicroReaction: Date = Date()
    private var nextIdleMicroReactionInterval: TimeInterval = 45.0
    private var idleMicroReactionToken: Int = 0
    var isPerformingIdleMicroReaction: Bool = false

    init() {
        startAnimations()
    }

    func stopAnimations() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startAnimations() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
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

        // Wiggle oscillates and decays back to rest for playful grumpy reactions.
        if abs(wigglePhase) > 0.001 {
            wigglePhase = -wigglePhase * 0.75
            if abs(wigglePhase) < 0.005 { wigglePhase = 0 }
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
            fallAsleep()
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

        // Subtle, low-frequency idle micro-reaction when calm and resting (every 40-75s)
        if motion > 0, restful, !isAsleep, activeReaction == nil,
           now.timeIntervalSince(lastInteraction) > 25.0,
           now.timeIntervalSince(lastIdleMicroReaction) > nextIdleMicroReactionInterval {
            triggerIdleMicroReaction(now: now)
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

    /// Pops a subtle, restrained celebratory bounce for task or command successes.
    func playRestrainedBounce() {
        guard AppState.shared.settings.motionScale > 0 else { return }
        bouncePhase = 0.45
    }

    /// Immediately zeroes any transient physical bouncing or wiggling (e.g. on task failure).
    func suppressMotion() {
        bouncePhase = 0
        wigglePhase = 0
    }

    func updateExpression(for newState: AMORAState) {
        if let active = activeReaction {
            // High-priority system states (priority >= 80, e.g. alert, speaking, error) override click reactions.
            if newState.priority >= 80 {
                activeReaction = nil
                activeReactionMessage = nil
                reactionRevertToken &+= 1
                previousStateBeforeReaction = nil
            } else if newState != active.state {
                self.state = newState
                return
            }
        }

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
        case .affection:
            newExpression = .affection()
        case .grumpy:
            newExpression = .grumpy()
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

    /// Triggers a discrete expressive mascot reaction to a user click or tap.
    @discardableResult
    func reactToClick(now: Date = Date(), forcedReaction: MascotReaction? = nil) -> MascotReaction? {
        let elapsed = now.timeIntervalSince(lastClickTime)
        guard elapsed >= clickDebounceThreshold else { return nil }

        if elapsed > 1.5 {
            rapidClickCount = 1
        } else {
            rapidClickCount += 1
        }
        lastClickTime = now
        noteInteraction()

        let chosen: MascotReaction
        if let forced = forcedReaction {
            chosen = forced
        } else if rapidClickCount >= 3 {
            chosen = .grumpy
            rapidClickCount = 0
        } else {
            let cycle: [MascotReaction] = [.affection, .excited, .curious, .grumpy]
            chosen = cycle[reactionCycleIndex % cycle.count]
            reactionCycleIndex += 1
        }

        triggerReaction(chosen)
        return chosen
    }

    func triggerReaction(_ reaction: MascotReaction) {
        if activeReaction == nil {
            previousStateBeforeReaction = state
        }
        activeReaction = reaction
        activeReactionMessage = reaction.expressiveMessage
        reactionRevertToken &+= 1
        let token = reactionRevertToken

        AppState.shared.stateManager.transition(to: reaction.state)
        self.expression = reaction.expression
        self.state = reaction.state

        let motion = AppState.shared.settings.motionScale
        if motion > 0 {
            switch reaction {
            case .affection:
                bouncePhase = 0.6
                wigglePhase = 0
            case .excited:
                playBounce()
                wigglePhase = 0
            case .curious:
                bouncePhase = 0.2
                wigglePhase = 0
                targetEyeDirection = CGPoint(x: 2.0, y: -1.5)
            case .grumpy:
                bouncePhase = 0
                wigglePhase = 0.18
            }
        } else {
            bouncePhase = 0
            wigglePhase = 0
        }

        SoundService.shared.play(reaction.sound)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.reactionRevertToken == token else { return }
            self.clearActiveReaction()
        }
    }

    func clearActiveReaction() {
        guard activeReaction != nil else { return }
        activeReaction = nil
        activeReactionMessage = nil
        let prev = previousStateBeforeReaction
        previousStateBeforeReaction = nil

        // If pre-reaction state was an explicit non-idle state (e.g. focused, music), restore it.
        // Otherwise, restore the current live ambient state.
        let revertState = (prev != nil && prev != .idle) ? prev! : PersonalityEngine.shared.currentAmbientState()

        if revertState == .idle {
            AppState.shared.stateManager.resetToIdle()
        } else {
            AppState.shared.stateManager.transition(to: revertState)
        }
        updateExpression(for: revertState)
    }

    func cancelIdleMicroReaction(restoreAmbient: Bool = true) {
        guard isPerformingIdleMicroReaction else { return }
        isPerformingIdleMicroReaction = false
        idleMicroReactionToken &+= 1
        targetEyeDirection = .zero
        if restoreAmbient {
            let ambient = PersonalityEngine.shared.currentAmbientState()
            updateExpression(for: ambient)
        }
    }

    func triggerIdleMicroReaction(now: Date = Date()) {
        lastIdleMicroReaction = now
        nextIdleMicroReactionInterval = Double.random(in: 40.0...75.0)
        guard activeReaction == nil, !isAsleep else { return }

        isPerformingIdleMicroReaction = true
        idleMicroReactionToken &+= 1
        let token = idleMicroReactionToken

        let roll = Double.random(in: 0...1)
        if roll < 0.5 {
            // Sleepy slow blink with gentle contented look
            blinkOnce(duration: 0.32)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.idleMicroReactionToken == token, self.isPerformingIdleMicroReaction else { return }
                self.isPerformingIdleMicroReaction = false
            }
        } else {
            // Playful subtle glance and soft smile
            targetEyeDirection = CGPoint(x: 1.5, y: -1.0)
            expression = Expression(
                eyes: .normal,
                eyeOffset: CGPoint(x: 1.5, y: -1.0),
                mouth: .smile,
                blinkProgress: 0,
                headTilt: 0.08,
                antennaPulse: 0.4
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self, self.idleMicroReactionToken == token, self.isPerformingIdleMicroReaction else { return }
                self.isPerformingIdleMicroReaction = false
                self.targetEyeDirection = .zero
                let ambient = PersonalityEngine.shared.currentAmbientState()
                self.updateExpression(for: ambient)
            }
        }
    }

    func resetForTesting() {
        activeReaction = nil
        activeReactionMessage = nil
        lastClickTime = .distantPast
        rapidClickCount = 0
        reactionCycleIndex = 0
        reactionRevertToken = 0
        previousStateBeforeReaction = nil
        bouncePhase = 0
        wigglePhase = 0
        eyeDirection = .zero
        targetEyeDirection = .zero
        isPerformingIdleMicroReaction = false
        idleMicroReactionToken = 0
        lastIdleMicroReaction = Date()
        nextIdleMicroReactionInterval = 45.0
        isAsleep = false
        updateExpression(for: .idle)
    }

    /// Transitions AMORA into sleep mode when idle or resting.
    func fallAsleep() {
        guard !isAsleep else { return }
        isAsleep = true
        AppState.shared.stateManager.transition(to: .sleepy)
        updateExpression(for: .sleepy)
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
        cancelIdleMicroReaction(restoreAmbient: true)
        if isAsleep {
            isAsleep = false
            let ambient = PersonalityEngine.shared.currentAmbientState()
            if ambient == .idle {
                AppState.shared.stateManager.resetToIdle()
            } else {
                AppState.shared.stateManager.transition(to: ambient)
            }
            updateExpression(for: ambient)
        }
    }
}
