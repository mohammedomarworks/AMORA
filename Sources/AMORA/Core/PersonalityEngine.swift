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
}

@Observable @MainActor
final class IslandActivityCenter {
    static let shared = IslandActivityCenter()

    /// A transient focus the user selected (e.g. tapped into a module).
    var userFocus: DynamicIslandMode?

    private init() {}

    var mode: DynamicIslandMode {
        let battery = BatteryService.shared
        if battery.hasBattery && !battery.isCharging && battery.level <= 10 {
            return .battery
        }
        if TimerService.shared.isRunning { return .timer }
        if let focus = userFocus { return focus }
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

    private init() {}

    func react(to event: AMORAEvent) {
        let now = Date()
        let r = reaction(for: event)

        // Expression is the primary channel — gated only to avoid rapid flip-flopping.
        if due(r.key + ".expr", every: r.exprCooldown, now: now) {
            AppState.shared.stateManager.transition(to: r.state)
            AMORARobot.shared.updateExpression(for: r.state)
            scheduleRevert(after: r.revert)
        }

        // Text + sound are the "loud" channel — gated hard so they stay special.
        if due(r.key + ".msg", every: r.messageCooldown, now: now) {
            if let m = r.message { showMessage(m) }
            if let s = r.sound { SoundService.shared.play(s) }
            if event == .timerCompleted { celebrationToken &+= 1 }
        }
    }

    /// Compatibility entry point for UI-only reactions. Service events should
    /// normally enter through AMORAEventCenter so context is updated first.
    func emit(_ event: AMORAEvent) {
        AMORAEventCenter.shared.emit(event)
    }

    // MARK: - Cooldown bookkeeping

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard let self, self.messageToken == token else { return }
            self.message = nil
        }
    }

    private func scheduleRevert(after seconds: TimeInterval) {
        guard seconds > 0 else { return }
        revertToken &+= 1
        let token = revertToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.revertToken == token else { return }
            // Return to calm only if the user isn't actively looking at the island.
            guard !IslandModel.shared.isExpanded else { return }
            AppState.shared.stateManager.resetToIdle()
            AMORARobot.shared.updateExpression(for: .idle)
        }
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
            return Reaction(key: "opened", state: .happy, message: "Hey!", sound: .open,
                            exprCooldown: 0, messageCooldown: 3600, revert: 0)
        case .closed:
            return Reaction(key: "closed", state: .idle, message: nil, sound: .close,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        case .timerStarted:
            return Reaction(key: "timerStart", state: .thinking, message: "Let's focus.", sound: nil,
                            exprCooldown: 2, messageCooldown: 2, revert: 3)
        case .timerPaused:
            return Reaction(key: "timerPause", state: .curious, message: "Timer paused.", sound: .click,
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
            return Reaction(key: "full", state: .happy, message: "All charged.", sound: .success,
                            exprCooldown: 300, messageCooldown: 3600, revert: 3)
        case .lowBattery:
            return Reaction(key: "low", state: .concerned, message: "We're getting low.", sound: nil,
                            exprCooldown: 600, messageCooldown: 900, revert: 4)
        case .criticalBattery:
            return Reaction(key: "critical", state: .alert, message: "Battery critical.", sound: .notification,
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
                            exprCooldown: 0, messageCooldown: 0, revert: 2)
        case .commandFailed:
            return Reaction(key: "commandFailed", state: .concerned, message: nil, sound: .notification,
                            exprCooldown: 0, messageCooldown: 0, revert: 2)
        case .clipboardRestored:
            return Reaction(key: "clip", state: .happy, message: "Copied.", sound: .click,
                            exprCooldown: 2, messageCooldown: 5, revert: 2)
        case .fileReceived:
            return Reaction(key: "file", state: .happy, message: "Got it.", sound: .pop,
                            exprCooldown: 2, messageCooldown: 2, revert: 3)
        case .clipboardUpdated, .noteCreated, .systemIdle, .systemActive:
            return Reaction(key: "quiet", state: .idle, message: nil, sound: nil,
                            exprCooldown: 0, messageCooldown: 0, revert: 0)
        }
    }

}
