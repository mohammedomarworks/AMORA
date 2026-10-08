import Foundation
import Observation

/// Central coordinator and runtime service for Proactive AMORA V1.
/// Manages proactive evaluation, cooldowns, suggestions, and Dynamic Island presentation.
/// Never creates memories automatically, never inspects clipboard or screen, and never executes shell commands.
@Observable @MainActor
public final class AmoraProactiveService: Sendable {
    public static let shared = AmoraProactiveService()

    public private(set) var currentSuggestion: AmoraProactiveSuggestion?
    public private(set) var lastInteractionDate: Date?

    public let cooldownTracker: any AmoraProactiveCooldownTracking
    public let evaluator: any AmoraProactiveEvaluating
    public let contextProvider: @MainActor () -> AmoraContextSnapshot
    public let memoryStore: any AmoraMemoryStoring
    public let settingsProvider: @MainActor () -> AmoraProactiveSettings
    public let clock: () -> Date
    public var onSuggestionPresented: (@MainActor (AmoraProactiveSuggestion) -> Void)?

    public init(
        cooldownTracker: (any AmoraProactiveCooldownTracking)? = nil,
        evaluator: (any AmoraProactiveEvaluating)? = nil,
        contextProvider: (@MainActor () -> AmoraContextSnapshot)? = nil,
        memoryStore: (any AmoraMemoryStoring)? = nil,
        settingsProvider: (@MainActor () -> AmoraProactiveSettings)? = nil,
        clock: (@Sendable () -> Date)? = nil,
        onSuggestionPresented: (@MainActor (AmoraProactiveSuggestion) -> Void)? = nil
    ) {
        self.cooldownTracker = cooldownTracker ?? AmoraProactiveCooldownTracker()
        self.evaluator = evaluator ?? AmoraProactiveEvaluator()
        self.contextProvider = contextProvider ?? { AmoraContextProvider.shared.currentSnapshot }
        self.memoryStore = memoryStore ?? AmoraMemoryStore()
        self.settingsProvider = settingsProvider ?? { AppState.shared.settings.proactiveSettingsSnapshot }
        self.clock = clock ?? { Date() }
        self.currentSuggestion = nil
        self.lastInteractionDate = nil
        self.onSuggestionPresented = onSuggestionPresented ?? { _ in
            if IslandModel.shared.displayState == .collapsed {
                WindowManager.shared.expandIsland()
            }
        }
    }

    /// Records an interaction timestamp to track user activity / inactivity.
    public func recordInteraction(at date: Date? = nil) {
        self.lastInteractionDate = date ?? clock()
    }

    /// Handles events emitted by `AMORAEventCenter`.
    func handleEvent(_ event: AMORAEvent) {
        let settings = settingsProvider()
        guard settings.isEnabled else { return }

        switch event {
        case .timerCompleted:
            Task { @MainActor in
                await self.evaluateTrigger(.timerCompleted)
            }

        case .timerNearlyFinished:
            Task { @MainActor in
                await self.evaluateTrigger(.timerNearlyFinished)
            }

        case .musicStarted, .musicPaused, .musicChanged, .musicStopped:
            Task { @MainActor in
                await self.evaluateTrigger(.musicPlaybackChanged)
            }

        case .criticalBattery:
            Task { @MainActor in
                await self.evaluateTrigger(.batteryCriticallyLow)
            }

        case .opened:
            // Evaluate inactivity return before updating lastInteractionDate
            Task { @MainActor in
                await self.evaluateTrigger(.inactivityReturn)
                self.recordInteraction(at: self.clock())
            }

        case .launched, .closed, .commandProcessing, .commandSucceeded, .aiThinking, .aiSucceeded:
            recordInteraction(at: clock())

        default:
            break
        }
    }

    /// Evaluates a specific proactive trigger.
    /// Returns the suggestion if produced and accepted, or nil if suppressed by cooldown, settings, priority, or condition.
    @discardableResult
    public func evaluateTrigger(_ trigger: AmoraProactiveTrigger) async -> AmoraProactiveSuggestion? {
        let settings = settingsProvider()
        guard settings.isTriggerEnabled(trigger) else {
            return nil
        }

        let now = clock()

        // 1. Check cooldown
        if cooldownTracker.isCoolingDown(key: trigger.rawValue, now: now) {
            return nil
        }

        // 2. Prevent duplicate notifications for identical active suggestion
        if let active = currentSuggestion, active.trigger == trigger {
            return nil
        }

        // 3. Obtain snapshot and read-only relevant memories
        let snapshot = contextProvider()
        let memories = await memoryStore.list()

        let context = AmoraProactiveEvaluationContext(
            snapshot: snapshot,
            memories: memories,
            lastInteractionDate: lastInteractionDate,
            settings: settings,
            now: now
        )

        // 4. Pure evaluation
        guard let candidate = evaluator.evaluate(trigger: trigger, context: context) else {
            return nil
        }

        // 5. Priority handling: candidate must have higher priority if a suggestion is currently active
        if let active = currentSuggestion {
            if candidate.priority > active.priority {
                self.currentSuggestion = candidate
                cooldownTracker.recordTrigger(key: candidate.trigger.rawValue, duration: candidate.cooldownDuration, now: now)
                onSuggestionPresented?(candidate)
                return candidate
            } else {
                // Lower or equal priority does not overwrite active suggestion
                return nil
            }
        } else {
            self.currentSuggestion = candidate
            cooldownTracker.recordTrigger(key: candidate.trigger.rawValue, duration: candidate.cooldownDuration, now: now)
            onSuggestionPresented?(candidate)
            return candidate
        }
    }

    /// Explicitly dismisses the current proactive suggestion.
    public func dismissCurrentSuggestion() {
        guard let current = currentSuggestion else { return }
        cooldownTracker.recordTrigger(key: current.trigger.rawValue, duration: current.cooldownDuration, now: clock())
        self.currentSuggestion = nil
    }

    /// Executes the safe action attached to the current proactive suggestion, if any.
    public func executeCurrentAction() async {
        guard let current = currentSuggestion, let action = current.action else { return }
        dismissCurrentSuggestion()
        _ = await AmoraActionEngine.shared.execute(action, context: AmoraActionContext(isConfirmed: true))
    }

    /// Resets runtime state for testing.
    public func reset() {
        self.currentSuggestion = nil
        self.lastInteractionDate = nil
        self.cooldownTracker.reset()
    }
}
