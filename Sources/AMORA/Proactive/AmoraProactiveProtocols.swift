import Foundation

/// Strongly typed proactive triggers supported by AMORA.
/// Only 5 initial triggers are permitted in Proactive AMORA V1.
public enum AmoraProactiveTrigger: String, CaseIterable, Codable, Sendable {
    case timerCompleted = "timer.completed"
    case timerNearlyFinished = "timer.nearly_finished"
    case musicPlaybackChanged = "music.playback_changed"
    case inactivityReturn = "amora.inactivity_return"
    case batteryCriticallyLow = "battery.critically_low"

    public var displayName: String {
        switch self {
        case .timerCompleted:
            return "Timer Completed"
        case .timerNearlyFinished:
            return "Timer Nearly Finished"
        case .musicPlaybackChanged:
            return "Music Playback Changes"
        case .inactivityReturn:
            return "Return After Inactivity"
        case .batteryCriticallyLow:
            return "Critically Low Battery"
        }
    }
}

/// Priority levels for proactive suggestions.
/// Higher priority suggestions supersede lower priority ones when displayed.
public enum AmoraProactivePriority: Int, Comparable, Codable, Sendable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public static func < (lhs: AmoraProactivePriority, rhs: AmoraProactivePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Strongly typed proactive suggestion presented inside the Dynamic Island.
public struct AmoraProactiveSuggestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let trigger: AmoraProactiveTrigger
    public let conditionDescription: String
    public let cooldownDuration: TimeInterval
    public let priority: AmoraProactivePriority
    public let message: String
    public let action: AmoraAction?
    public let actionTitle: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        trigger: AmoraProactiveTrigger,
        conditionDescription: String,
        cooldownDuration: TimeInterval,
        priority: AmoraProactivePriority,
        message: String,
        action: AmoraAction? = nil,
        actionTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.trigger = trigger
        self.conditionDescription = conditionDescription
        self.cooldownDuration = cooldownDuration
        self.priority = priority
        self.message = message
        self.action = action
        self.actionTitle = actionTitle
        self.createdAt = createdAt
    }
}

/// Strongly typed configuration for Proactive AMORA.
/// Defaults to conservative behavior:
/// - Cooldowns: conservative (e.g. 5 minutes minimum default)
/// - Inactivity return threshold: 30 minutes (1800s)
/// - Critical battery threshold: 10%
/// - Timer nearly finished threshold: 60 seconds
public struct AmoraProactiveSettings: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var timerCompletedEnabled: Bool
    public var timerNearlyFinishedEnabled: Bool
    public var musicPlaybackEnabled: Bool
    public var inactivityReturnEnabled: Bool
    public var batteryCriticalEnabled: Bool

    public var inactivityThresholdSeconds: TimeInterval
    public var batteryCriticalThresholdPercent: Int
    public var timerNearlyFinishedThresholdSeconds: Int
    public var defaultCooldownSeconds: TimeInterval

    public init(
        isEnabled: Bool = true,
        timerCompletedEnabled: Bool = true,
        timerNearlyFinishedEnabled: Bool = true,
        musicPlaybackEnabled: Bool = true,
        inactivityReturnEnabled: Bool = true,
        batteryCriticalEnabled: Bool = true,
        inactivityThresholdSeconds: TimeInterval = 1800,
        batteryCriticalThresholdPercent: Int = 10,
        timerNearlyFinishedThresholdSeconds: Int = 60,
        defaultCooldownSeconds: TimeInterval = 300
    ) {
        self.isEnabled = isEnabled
        self.timerCompletedEnabled = timerCompletedEnabled
        self.timerNearlyFinishedEnabled = timerNearlyFinishedEnabled
        self.musicPlaybackEnabled = musicPlaybackEnabled
        self.inactivityReturnEnabled = inactivityReturnEnabled
        self.batteryCriticalEnabled = batteryCriticalEnabled
        self.inactivityThresholdSeconds = inactivityThresholdSeconds
        self.batteryCriticalThresholdPercent = batteryCriticalThresholdPercent
        self.timerNearlyFinishedThresholdSeconds = timerNearlyFinishedThresholdSeconds
        self.defaultCooldownSeconds = defaultCooldownSeconds
    }

    public static let conservative = AmoraProactiveSettings()

    public func isTriggerEnabled(_ trigger: AmoraProactiveTrigger) -> Bool {
        guard isEnabled else { return false }
        switch trigger {
        case .timerCompleted:
            return timerCompletedEnabled
        case .timerNearlyFinished:
            return timerNearlyFinishedEnabled
        case .musicPlaybackChanged:
            return musicPlaybackEnabled
        case .inactivityReturn:
            return inactivityReturnEnabled
        case .batteryCriticallyLow:
            return batteryCriticalEnabled
        }
    }
}

/// Evaluation context supplied to proactive evaluator.
/// Builds strictly upon existing `AmoraContextSnapshot` and explicitly saved memories.
public struct AmoraProactiveEvaluationContext: Sendable {
    public let snapshot: AmoraContextSnapshot
    public let memories: [AmoraMemoryItem]
    public let lastInteractionDate: Date?
    public let settings: AmoraProactiveSettings
    public let now: Date

    public init(
        snapshot: AmoraContextSnapshot,
        memories: [AmoraMemoryItem] = [],
        lastInteractionDate: Date? = nil,
        settings: AmoraProactiveSettings = .conservative,
        now: Date = Date()
    ) {
        self.snapshot = snapshot
        self.memories = memories
        self.lastInteractionDate = lastInteractionDate
        self.settings = settings
        self.now = now
    }
}

/// Protocol for evaluating triggers into proactive suggestions.
public protocol AmoraProactiveEvaluating: Sendable {
    func evaluate(
        trigger: AmoraProactiveTrigger,
        context: AmoraProactiveEvaluationContext
    ) -> AmoraProactiveSuggestion?
}

/// Protocol for tracking cooldowns per trigger condition.
public protocol AmoraProactiveCooldownTracking: Sendable {
    func isCoolingDown(key: String, now: Date) -> Bool
    func recordTrigger(key: String, duration: TimeInterval, now: Date)
    func reset()
}
