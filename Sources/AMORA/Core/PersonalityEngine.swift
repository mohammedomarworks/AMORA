import Foundation
import SwiftUI
import Observation

/// The highest-priority thing AMORA is currently reflecting. Views read this to
/// decide which "hero" to surface. It is derived live from service state, so no
/// extra polling is needed — Observation tracks the service reads for us.
///
/// Priority (high → low): critical battery › active timer › user-selected focus
/// › active music › normal.
enum DynamicIslandMode: Equatable {
    case normal
    case music
    case timer
    case battery
    case notification
    case system
    case aiThinking
    case aiResponse
    case aiError
}

@Observable @MainActor
final class IslandActivityCenter {
    static let shared = IslandActivityCenter()

    /// A transient focus the user selected (e.g. tapped into a module).
    var userFocus: DynamicIslandMode?

    private init() {}

    var mode: DynamicIslandMode {
        switch AMORAContext.shared.assistantState {
        case .thinking: return .aiThinking
        case .responding: return .aiResponse
        case .failed: return .aiError
        case .idle, .cancelled: break
        }
        let battery = BatteryService.shared
        if battery.hasBattery && !battery.isCharging && battery.level <= 10 {
            return .battery
        }
        if TimerService.shared.isRunning { return .timer }
        if let focus = userFocus { return focus }
        if AmoraAutomationService.shared.currentNotification != nil || AmoraProactiveService.shared.currentSuggestion != nil {
            return .notification
        }
        if MusicService.shared.isPlaying { return .music }
        return .normal
    }
}

/// Meaningful moments AMORA can react to. The engine owns the mapping from event
/// to expression / message / sound, plus the cooldowns that keep it from nagging.
/// Lightweight "brain" that turns events into character. Reactions are mostly
/// expression + animation; text is the rare exception. Per-event cooldowns stop
/// AMORA from greeting on every open or alarming on every battery tick.
@Observable @MainActor
final class PersonalityEngine {
    static let shared = PersonalityEngine()

    /// A short line surfaced in the expanded island header. Auto-expires.
    private(set) var message: String?
    /// Bumped to ask the visible island to play a one-shot celebration.
    private(set) var celebrationToken: Int = 0

    private var cooldowns: [String: Date] = [:]
    private var messageToken = 0
    private var revertToken = 0
    private var lastEvent: AMORAEvent?
    private var lastEventTime: Date = .distantPast
    private var lastSound: AMORASound?
    private var lastSoundTime: Date = .distantPast

    private init() {}

    func react(to event: AMORAEvent) {
        let now = Date()

        // Cancel any in-progress idle micro-reaction immediately
        AMORARobot.shared.cancelIdleMicroReaction(restoreAmbient: false)

        // Suppress rapid identical event spam (e.g. repeated progress or status triggers within 350ms)
        if event == lastEvent && now.timeIntervalSince(lastEventTime) < 0.35 {
            return
        }
        lastEvent = event
        lastEventTime = now

        let r = reaction(for: event)
        let currentState = AppState.shared.stateManager.currentState

        // Critical safety alerts (priority >= 90, e.g. alert, error) take precedence over general task/routine events.
        // Explicit dismissal, cancellation, closure, or battery recovery events are permitted through to restore normal operation.
        let isDismissalOrRecoveryEvent = (
            event == .automationNotificationDismissed ||
            event == .proactiveSuggestionDismissed ||
            event == .aiCancelled ||
            event == .closed ||
            event == .charging ||
            event == .chargedFull
        )
        if currentState.priority >= 90 && r.state.priority < currentState.priority && !isDismissalOrRecoveryEvent {
            return
        }

        // Timer completion is a major user milestone: clears any active click reaction to show celebration
        if event == .timerCompleted {
            AMORARobot.shared.clearActiveReaction()
        }

        // Expression is the primary channel — gated only to avoid rapid flip-flopping.
        if due(r.key + ".expr", every: r.exprCooldown, now: now) {
            AppState.shared.stateManager.transition(to: r.state)
            AMORARobot.shared.updateExpression(for: r.state)
            scheduleRevert(after: r.revert)

            // Context-driven physical movement (respects Reduce Motion inside robot helpers)
            // Guarded so routine background events do not interrupt an active user click reaction
            if AMORARobot.shared.activeReaction == nil || r.state.priority >= 75 {
                switch event {
                case .timerCompleted:
                    AMORARobot.shared.playBounce()
                case .commandSucceeded, .aiSucceeded:
                    AMORARobot.shared.playRestrainedBounce()
                case .commandFailed, .aiFailed:
                    AMORARobot.shared.suppressMotion()
                default:
                    break
                }
            }
        }

        // Text + sound are the "loud" channel — gated hard so they stay special.
        // Also guarded so routine background events do not speak over an active user click reaction.
        if due(r.key + ".msg", every: r.messageCooldown, now: now) {
            let isClickReactionActive = (AMORARobot.shared.activeReaction != nil && r.state.priority < 75)
            if !isClickReactionActive {
                if let m = r.message { showMessage(m) }
                if let s = r.sound { playSound(s, for: r.state, now: now) }
                if event == .timerCompleted { celebrationToken &+= 1 }
            }
        }
    }

    /// Compatibility entry point for UI-only reactions. Service events should
    /// normally enter through AMORAEventCenter so context is updated first.
    func emit(_ event: AMORAEvent) {
        AMORAEventCenter.shared.emit(event)
    }

    // MARK: - Cooldown bookkeeping

    func resetForTesting() {
        cooldowns.removeAll()
        message = nil
        celebrationToken = 0
        messageToken = 0
        revertToken = 0
        lastEvent = nil
        lastEventTime = .distantPast
        lastSound = nil
        lastSoundTime = .distantPast
    }

    private func playSound(_ sound: AMORASound, for state: AMORAState, now: Date) {
        let elapsed = now.timeIntervalSince(lastSoundTime)
        // Suppress identical duplicate sound within 350ms
        if sound == lastSound && elapsed < 0.35 {
            return
        }
        // Avoid sound collision: suppress clicks if another sound played within 100ms
        if elapsed < 0.10 && sound == .click {
            return
        }
        lastSound = sound
        lastSoundTime = now
        SoundService.shared.play(sound)
    }

    private func due(_ key: String, every seconds: TimeInterval, now: Date) -> Bool {
        if seconds > 0, let last = cooldowns[key], now.timeIntervalSince(last) < seconds {
            return false
        }
        cooldowns[key] = now
        return true
    }

    private func showMessage(_ text: String) {
        message = text
        messageToken &+= 1
        let token = messageToken
        let linger = max(4.0, min(9.0, Double(text.count) * 0.08))
        DispatchQueue.main.asyncAfter(deadline: .now() + linger) { [weak self] in
            guard let self, self.messageToken == token else { return }
            self.message = nil
        }
    }

    private func scheduleRevert(after seconds: TimeInterval) {
        revertToken &+= 1
        guard seconds > 0 else { return }
        let token = revertToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.revertToken == token else { return }
            self.restoreAmbientState()
        }
    }

    /// Determines the natural ambient state based on live application and system conditions.
    func currentAmbientState() -> AMORAState {
        if let activeReaction = AMORARobot.shared.activeReaction {
            return activeReaction.state
        }
        let battery = BatteryService.shared
        if battery.hasBattery && !battery.isCharging && battery.level <= 10 {
            return .alert
        }
        if AmoraAutomationService.shared.currentNotification != nil {
            return .alert
        }
        if AssistantManager.shared.state == .thinking {
            return .aiThinking
        }
        if AmoraActionExecutionCoordinator.shared.state == .executing {
            return .thinking
        }
        if TimerService.shared.isRunning {
            return .focused
        }
        if MusicService.shared.isPlaying {
            return .music
        }
        if IslandModel.shared.isExpanded {
            return .expanded
        }
        if AMORARobot.shared.isAsleep {
            return .sleepy
        }
        if AMORARobot.shared.isHovering {
            return .hover
        }
        return .idle
    }

    func restoreAmbientState() {
        let ambient = currentAmbientState()
        if ambient == .idle {
            AppState.shared.stateManager.resetToIdle()
        } else {
            AppState.shared.stateManager.transition(to: ambient)
        }
        AMORARobot.shared.updateExpression(for: ambient)
    }

    func forceRevertForTesting() {
        restoreAmbientState()
    }
    // MARK: - Event table

    private struct Reaction {
        let key: String
        let state: AMORAState
        let message: String?
        let sound: AMORASound?
        let exprCooldown: TimeInterval
        let messageCooldown: TimeInterval
        let revert: TimeInterval
    }

    private func reaction(for event: AMORAEvent) -> Reaction {
        switch event {
        case .launched:
            return Reaction(key: "launched", state: .happy, message: "Ready.", sound: .pop,
                            exprCooldown: 0, messageCooldown: 0, revert: 3)
        case .opened:
            return Reaction(key: "opened", state: .expanded, message: nil, sound: .open,
                            exprCooldown: 0, messageCooldown: 3600, revert: 0)
        case .closed:
            return Reaction(key: "closed", state: .idle, message: nil, sound: .close,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        case .timerStarted:
            return Reaction(key: "timerStart", state: .thinking, message: "Let's focus.", sound: nil,
                            exprCooldown: 2, messageCooldown: 2, revert: 3)
        case .timerPaused:
            return Reaction(key: "timerPause", state: .curious, message: "Paused.", sound: .click,
                            exprCooldown: 1, messageCooldown: 1, revert: 2)
        case .timerResumed:
            return Reaction(key: "timerResume", state: .focused, message: "Back to it.", sound: .click,
                            exprCooldown: 1, messageCooldown: 1, revert: 2)
        case .timerCompleted:
            return Reaction(key: "timerDone", state: .excited, message: "Focus session complete! ✨", sound: .timerComplete,
                            exprCooldown: 1, messageCooldown: 1, revert: 5)
        case .charging:
            return Reaction(key: "charging", state: .happy, message: "Charging up.", sound: nil,
                            exprCooldown: 60, messageCooldown: 300, revert: 3)
        case .chargedFull:
            return Reaction(key: "full", state: .happy, message: "Fully charged.", sound: .success,
                            exprCooldown: 300, messageCooldown: 3600, revert: 3)
        case .lowBattery:
            return Reaction(key: "low", state: .concerned, message: "Battery is low — let's plug in soon.", sound: nil,
                            exprCooldown: 600, messageCooldown: 900, revert: 4)
        case .criticalBattery:
            return Reaction(key: "critical", state: .alert, message: "Battery critical — please plug in now.", sound: .notification,
                            exprCooldown: 300, messageCooldown: 600, revert: 4)
        case .musicStarted:
            return Reaction(key: "musicOn", state: .music, message: nil, sound: nil,
                            exprCooldown: 30, messageCooldown: 120, revert: 0)
        case .musicPaused:
            return Reaction(key: "musicPause", state: .curious, message: "Music paused.", sound: .click,
                            exprCooldown: 2, messageCooldown: 2, revert: 2)
        case .musicChanged:
            return Reaction(key: "musicChange", state: .curious, message: nil, sound: nil,
                            exprCooldown: 2, messageCooldown: 2, revert: 0)
        case .musicStopped:
            return Reaction(key: "musicOff", state: .idle, message: nil, sound: nil,
                            exprCooldown: 30, messageCooldown: 120, revert: 0)
        case .commandProcessing:
            return Reaction(key: "commandProcessing", state: .thinking, message: nil, sound: .click,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        case .commandSucceeded:
            return Reaction(key: "commandSucceeded", state: .happy, message: nil, sound: .success,
                            exprCooldown: 0.25, messageCooldown: 0.25, revert: 2.5)
        case .commandFailed:
            return Reaction(key: "commandFailed", state: .concerned, message: nil, sound: .notification,
                            exprCooldown: 0.25, messageCooldown: 0.25, revert: 2.5)
        case .aiThinking:
            return Reaction(key: "aiThinking", state: .aiThinking, message: nil, sound: .click,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        case .aiSucceeded:
            return Reaction(key: "aiSucceeded", state: .aiResponse, message: nil, sound: .success,
                            exprCooldown: 0.25, messageCooldown: 0.25, revert: 2.5)
        case .aiFailed:
            return Reaction(key: "aiFailed", state: .aiError, message: nil, sound: .notification,
                            exprCooldown: 0.25, messageCooldown: 0.25, revert: 2.5)
        case .aiCancelled:
            return Reaction(key: "aiCancelled", state: .sad, message: "Cancelled.", sound: .sad,
                            exprCooldown: 0.25, messageCooldown: 0.25, revert: 2.0)
        case .proactiveSuggestionPresented:
            return Reaction(key: "proactivePresented", state: .curious, message: nil, sound: .notification,
                            exprCooldown: 0, messageCooldown: 1, revert: 5)
        case .proactiveSuggestionDismissed:
            return Reaction(key: "proactiveDismissed", state: .idle, message: nil, sound: nil,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        case .automationNotificationPresented:
            return Reaction(key: "autoPresented", state: .alert, message: nil, sound: .notification,
                            exprCooldown: 0, messageCooldown: 1, revert: 5)
        case .automationNotificationDismissed:
            return Reaction(key: "autoDismissed", state: .idle, message: nil, sound: nil,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        case .clipboardRestored:
            return Reaction(key: "clip", state: .happy, message: "Copied.", sound: .click,
                            exprCooldown: 2, messageCooldown: 5, revert: 2)
        case .fileReceived:
            return Reaction(key: "file", state: .happy, message: "Got it.", sound: .pop,
                            exprCooldown: 2, messageCooldown: 2, revert: 3)
        case .clipboardUpdated, .noteCreated, .systemIdle, .systemActive, .timerNearlyFinished:
            return Reaction(key: "quiet", state: .idle, message: nil, sound: nil,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        }
    }

}
