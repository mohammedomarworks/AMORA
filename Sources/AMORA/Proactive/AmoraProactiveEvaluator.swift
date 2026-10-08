import Foundation

/// Pure deterministic evaluator for Proactive AMORA triggers.
/// Evaluates snapshots, explicitly saved memories, and settings to produce suggestions.
/// Never creates memories, never inspects clipboard, never reads screen or arbitrary files.
public struct AmoraProactiveEvaluator: AmoraProactiveEvaluating {
    public init() {}

    public func evaluate(
        trigger: AmoraProactiveTrigger,
        context: AmoraProactiveEvaluationContext
    ) -> AmoraProactiveSuggestion? {
        guard context.settings.isTriggerEnabled(trigger) else {
            return nil
        }

        switch trigger {
        case .timerCompleted:
            return evaluateTimerCompleted(context: context)

        case .timerNearlyFinished:
            return evaluateTimerNearlyFinished(context: context)

        case .musicPlaybackChanged:
            return evaluateMusicPlaybackChanged(context: context)

        case .inactivityReturn:
            return evaluateInactivityReturn(context: context)

        case .batteryCriticallyLow:
            return evaluateBatteryCriticallyLow(context: context)
        }
    }

    // MARK: - 1. Timer Completed
    private func evaluateTimerCompleted(context: AmoraProactiveEvaluationContext) -> AmoraProactiveSuggestion? {
        // Explicit memory integration: check for explicitly saved break preferences
        let breakMemory = context.memories.first {
            let key = $0.key.lowercased()
            return key.contains("break") || key.contains("rest")
        }

        let breakDurationSeconds: TimeInterval
        let message: String

        if let breakMemory {
            breakDurationSeconds = parseDurationSeconds(from: breakMemory.value) ?? 300
            message = "Focus timer completed! Time for your \(breakMemory.value) break."
        } else {
            breakDurationSeconds = 300 // default safe 5-minute break
            message = "Focus timer completed! Take a quick 5-minute break?"
        }

        return AmoraProactiveSuggestion(
            trigger: .timerCompleted,
            conditionDescription: "Focus timer completed",
            cooldownDuration: 120,
            priority: .high,
            message: message,
            action: .startTimer(duration: breakDurationSeconds),
            actionTitle: "Start Break",
            createdAt: context.now
        )
    }

    // MARK: - 2. Timer Nearly Finished
    private func evaluateTimerNearlyFinished(context: AmoraProactiveEvaluationContext) -> AmoraProactiveSuggestion? {
        guard let timer = context.snapshot.timer,
              timer.running,
              timer.remainingSeconds > 0,
              timer.remainingSeconds <= context.settings.timerNearlyFinishedThresholdSeconds else {
            return nil
        }

        return AmoraProactiveSuggestion(
            trigger: .timerNearlyFinished,
            conditionDescription: "Timer remaining seconds <= \(context.settings.timerNearlyFinishedThresholdSeconds)s",
            cooldownDuration: 180,
            priority: .medium,
            message: "Focus timer is almost done (\(timer.remainingSeconds)s remaining).",
            action: nil,
            actionTitle: nil,
            createdAt: context.now
        )
    }

    // MARK: - 3. Music Playback Changed
    private func evaluateMusicPlaybackChanged(context: AmoraProactiveEvaluationContext) -> AmoraProactiveSuggestion? {
        guard let media = context.snapshot.media,
              media.source.lowercased() != "none",
              media.state.lowercased() != "inactive" else {
            return nil
        }

        let isPlaying = media.isPlaying
        let message: String
        let action: AmoraAction
        let actionTitle: String

        if isPlaying {
            if let title = media.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let artistSuffix = media.artist.map { " — \($0)" } ?? ""
                message = "Now playing: \(title)\(artistSuffix)"
            } else {
                message = "Music is playing on \(media.source)."
            }
            action = .pauseMusic
            actionTitle = "Pause"
        } else {
            message = "Music is \(media.state) on \(media.source)."
            action = .playMusic
            actionTitle = "Play"
        }

        return AmoraProactiveSuggestion(
            trigger: .musicPlaybackChanged,
            conditionDescription: "Media playback state is \(media.state) on \(media.source)",
            cooldownDuration: 120,
            priority: .low,
            message: message,
            action: action,
            actionTitle: actionTitle,
            createdAt: context.now
        )
    }

    // MARK: - 4. Inactivity Return
    private func evaluateInactivityReturn(context: AmoraProactiveEvaluationContext) -> AmoraProactiveSuggestion? {
        guard let lastInteraction = context.lastInteractionDate else {
            return nil
        }

        let elapsed = context.now.timeIntervalSince(lastInteraction)
        guard elapsed >= context.settings.inactivityThresholdSeconds else {
            return nil
        }

        // Explicit memory integration: check for task or project focus preference
        let taskMemory = context.memories.first {
            let key = $0.key.lowercased()
            return key.contains("project") || key.contains("task") || key.contains("goal") || key.contains("focus")
        }

        let message: String
        if let taskMemory {
            message = "Welcome back! Continue working on \(taskMemory.value)?"
        } else {
            message = "Welcome back! Ready for a focused session?"
        }

        return AmoraProactiveSuggestion(
            trigger: .inactivityReturn,
            conditionDescription: "Inactivity elapsed >= \(Int(context.settings.inactivityThresholdSeconds / 60)) minutes",
            cooldownDuration: 1800,
            priority: .low,
            message: message,
            action: .startTimer(duration: 1500),
            actionTitle: "Start 25m Focus",
            createdAt: context.now
        )
    }

    // MARK: - 5. Battery Critically Low
    private func evaluateBatteryCriticallyLow(context: AmoraProactiveEvaluationContext) -> AmoraProactiveSuggestion? {
        guard let battery = context.snapshot.battery,
              let percent = battery.percent,
              percent <= context.settings.batteryCriticalThresholdPercent,
              !battery.charging,
              battery.isPluggedIn != true else {
            return nil
        }

        return AmoraProactiveSuggestion(
            trigger: .batteryCriticallyLow,
            conditionDescription: "Battery percent <= \(context.settings.batteryCriticalThresholdPercent)% and not charging",
            cooldownDuration: 600,
            priority: .critical,
            message: "Battery is critically low (\(percent)%). Connect to power.",
            action: nil,
            actionTitle: nil,
            createdAt: context.now
        )
    }

    // MARK: - Duration parsing helper
    private func parseDurationSeconds(from string: String) -> TimeInterval? {
        let cleaned = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: cleaned)
        guard let number = scanner.scanInt() else { return nil }
        if cleaned.contains("hour") || cleaned.contains("hr") {
            return TimeInterval(number * 3600)
        } else if cleaned.contains("second") || cleaned.contains("sec") {
            return TimeInterval(number)
        } else {
            // Default assumes minutes
            return TimeInterval(number * 60)
        }
    }
}
