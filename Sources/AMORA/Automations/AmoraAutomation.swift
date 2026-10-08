import Foundation

/// Comparison operator used for battery threshold automations.
public enum BatteryComparison: String, Codable, Equatable, Sendable, CaseIterable {
    case dropsBelow = "drops_below"
    case risesAbove = "rises_above"
    case lessThanOrEqual = "less_than_or_equal"
    case greaterThanOrEqual = "greater_than_or_equal"

    public var displayName: String {
        switch self {
        case .dropsBelow, .lessThanOrEqual: return "drops below or reaches"
        case .risesAbove, .greaterThanOrEqual: return "rises above or reaches"
        }
    }
}

/// Permitted V1 triggers for AMORA Automations.
public enum AmoraAutomationTrigger: Codable, Equatable, Sendable {
    case oneTime(date: Date)
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case interval(seconds: TimeInterval)
    case batteryThreshold(level: Int, comparison: BatteryComparison)
    case timerCompletion

    public var displayName: String {
        switch self {
        case .oneTime(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "At \(formatter.string(from: date))"
        case .daily(let h, let m):
            let period = h >= 12 ? "PM" : "AM"
            let hour12 = h % 12 == 0 ? 12 : h % 12
            return String(format: "Daily at %d:%02d %@", hour12, m, period)
        case .weekdays(let h, let m):
            let period = h >= 12 ? "PM" : "AM"
            let hour12 = h % 12 == 0 ? 12 : h % 12
            return String(format: "Weekdays at %d:%02d %@", hour12, m, period)
        case .interval(let s):
            if s >= 3600 {
                let hours = Int(s / 3600)
                return "Every \(hours) hour\(hours == 1 ? "" : "s")"
            } else if s >= 60 {
                let mins = Int(s / 60)
                return "Every \(mins) min\(mins == 1 ? "" : "s")"
            }
            return "Every \(Int(s)) seconds"
        case .batteryThreshold(let level, let comp):
            return "Battery \(comp.displayName) \(level)%"
        case .timerCompletion:
            return "When focus timer completes"
        }
    }

    public var systemImage: String {
        switch self {
        case .oneTime: return "calendar"
        case .daily: return "clock"
        case .weekdays: return "calendar.badge.clock"
        case .interval: return "arrow.clockwise"
        case .batteryThreshold: return "battery.50"
        case .timerCompletion: return "timer"
        }
    }

    public var defaultSchedule: AmoraAutomationSchedule? {
        switch self {
        case .oneTime(let date):
            return .oneTime(date: date)
        case .daily(let h, let m):
            return .daily(hour: h, minute: m)
        case .weekdays(let h, let m):
            return .weekdays(hour: h, minute: m)
        case .interval(let s):
            return .interval(seconds: s)
        case .batteryThreshold, .timerCompletion:
            return nil
        }
    }
}

/// Strongly typed schedule for periodic or scheduled automations.
public enum AmoraAutomationSchedule: Codable, Equatable, Sendable {
    case oneTime(date: Date)
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case interval(seconds: TimeInterval)

    /// Deterministically calculates the next timestamp when this schedule should run.
    public func calculateNextRunAt(
        from referenceDate: Date,
        lastRunAt: Date? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .oneTime(let targetDate):
            if targetDate > referenceDate {
                return targetDate
            }
            return nil

        case .daily(let hour, let minute):
            var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            comps.nanosecond = 0
            guard let targetToday = calendar.date(from: comps) else { return nil }
            if targetToday > referenceDate {
                return targetToday
            } else {
                return calendar.date(byAdding: .day, value: 1, to: targetToday)
            }

        case .weekdays(let hour, let minute):
            var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            comps.nanosecond = 0
            guard let candidate = calendar.date(from: comps) else { return nil }

            if candidate > referenceDate && !calendar.isDateInWeekend(candidate) {
                return candidate
            } else {
                for dayOffset in 1...7 {
                    if let nextCandidate = calendar.date(byAdding: .day, value: dayOffset, to: candidate) {
                        if nextCandidate > referenceDate && !calendar.isDateInWeekend(nextCandidate) {
                            return nextCandidate
                        }
                    }
                }
            }
            return nil

        case .interval(let seconds):
            guard seconds > 0 else { return nil }
            if let lastRunAt {
                if lastRunAt.addingTimeInterval(seconds) > referenceDate {
                    return lastRunAt.addingTimeInterval(seconds)
                } else {
                    let elapsed = referenceDate.timeIntervalSince(lastRunAt)
                    let intervalsPassed = max(1.0, ceil(elapsed / seconds))
                    return lastRunAt.addingTimeInterval(intervalsPassed * seconds)
                }
            } else {
                return referenceDate.addingTimeInterval(seconds)
            }
        }
    }
}

/// Permitted V1 actions for AMORA Automations.
/// Arbitrary shell commands, scripts, or unvetted process executions are strictly forbidden.
public enum AmoraAutomationAction: Codable, Equatable, Sendable {
    case showNotification(message: String)
    case startTimer(duration: TimeInterval)
    case openApp(name: String)
    case openWorkspace(section: String? = nil)
    case mediaPlay
    case mediaPause
    case mediaNext
    case mediaPrevious

    public var asAmoraAction: AmoraAction {
        switch self {
        case .showNotification(let msg):
            return .showNotification(message: msg)
        case .startTimer(let duration):
            return .startTimer(duration: duration)
        case .openApp(let name):
            return .openApplication(name: name)
        case .openWorkspace(let section):
            return .openWorkspace(section: section)
        case .mediaPlay:
            return .playMusic
        case .mediaPause:
            return .pauseMusic
        case .mediaNext:
            return .nextTrack
        case .mediaPrevious:
            return .previousTrack
        }
    }

    public init?(from amoraAction: AmoraAction) {
        switch amoraAction {
        case .showNotification(let msg):
            self = .showNotification(message: msg)
        case .startTimer(let duration):
            self = .startTimer(duration: duration)
        case .openApplication(let name):
            self = .openApp(name: name)
        case .openWorkspace(let section):
            self = .openWorkspace(section: section)
        case .playMusic:
            self = .mediaPlay
        case .pauseMusic:
            self = .mediaPause
        case .nextTrack:
            self = .mediaNext
        case .previousTrack:
            self = .mediaPrevious
        default:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .showNotification(let msg):
            return "Notification: \"\(msg)\""
        case .startTimer(let duration):
            let mins = Int(duration / 60)
            if mins > 0 {
                return "Start \(mins) min timer"
            }
            return "Start \(Int(duration))s timer"
        case .openApp(let name):
            return "Open \(name)"
        case .openWorkspace(let section):
            if let section, !section.isEmpty {
                return "Open Workspace (\(section.capitalized))"
            }
            return "Open Workspace"
        case .mediaPlay:
            return "Play Music"
        case .mediaPause:
            return "Pause Music"
        case .mediaNext:
            return "Next Track"
        case .mediaPrevious:
            return "Previous Track"
        }
    }

    public var systemImage: String {
        switch self {
        case .showNotification: return "bell.badge"
        case .startTimer: return "timer"
        case .openApp: return "app.badge"
        case .openWorkspace: return "macwindow"
        case .mediaPlay: return "play.fill"
        case .mediaPause: return "pause.fill"
        case .mediaNext: return "forward.fill"
        case .mediaPrevious: return "backward.fill"
        }
    }
}

/// Optional condition guarding automation execution.
public enum AmoraAutomationCondition: Codable, Equatable, Sendable {
    case batteryLevel(level: Int, comparison: BatteryComparison)
    case mediaPlaying(Bool)
    case frontmostApp(name: String)

    public func evaluate(snapshot: AmoraContextSnapshot) -> Bool {
        switch self {
        case .batteryLevel(let target, let comp):
            guard let level = snapshot.battery?.percent else { return false }
            switch comp {
            case .dropsBelow, .lessThanOrEqual:
                return level <= target
            case .risesAbove, .greaterThanOrEqual:
                return level >= target
            }
        case .mediaPlaying(let expected):
            return (snapshot.media?.isPlaying ?? false) == expected
        case .frontmostApp(let name):
            guard let active = snapshot.currentApplication?.name else { return false }
            return active.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}

/// Strongly typed, user-controlled persistent automation model.
public struct AmoraAutomation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var trigger: AmoraAutomationTrigger
    public var condition: AmoraAutomationCondition?
    public var action: AmoraAutomationAction
    public var schedule: AmoraAutomationSchedule?
    public var enabled: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var lastRunAt: Date?
    public var nextRunAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: AmoraAutomationTrigger,
        condition: AmoraAutomationCondition? = nil,
        action: AmoraAutomationAction,
        schedule: AmoraAutomationSchedule? = nil,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trigger = trigger
        self.condition = condition
        self.action = action
        let resolvedSchedule = schedule ?? trigger.defaultSchedule
        self.schedule = resolvedSchedule
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt

        if let nextRunAt {
            self.nextRunAt = nextRunAt
        } else if enabled {
            self.nextRunAt = resolvedSchedule?.calculateNextRunAt(
                from: lastRunAt ?? createdAt,
                lastRunAt: lastRunAt,
                calendar: calendar
            )
        } else {
            self.nextRunAt = nil
        }
    }

    /// Recalculates nextRunAt deterministically from the given reference date.
    public mutating func updateNextRunAt(from referenceDate: Date = Date(), calendar: Calendar = .current) {
        guard enabled else {
            self.nextRunAt = nil
            return
        }
        let resolvedSchedule = schedule ?? trigger.defaultSchedule
        self.nextRunAt = resolvedSchedule?.calculateNextRunAt(
            from: referenceDate,
            lastRunAt: lastRunAt,
            calendar: calendar
        )
    }
}

/// Errors occurring during automation store and service operations.
public enum AmoraAutomationError: Error, LocalizedError, Equatable {
    case duplicateAutomation(String)
    case notFound(UUID)
    case invalidAction(String)
    case invalidTrigger(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateAutomation(let msg): return msg
        case .notFound(let id): return "Automation with ID \(id) not found."
        case .invalidAction(let msg): return msg
        case .invalidTrigger(let msg): return msg
        }
    }
}
