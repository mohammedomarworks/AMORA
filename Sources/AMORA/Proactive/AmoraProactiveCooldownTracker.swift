import Foundation

/// Thread-safe tracker preventing repeated notifications for the same condition.
public final class AmoraProactiveCooldownTracker: AmoraProactiveCooldownTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var cooldowns: [String: (firedAt: Date, duration: TimeInterval)] = [:]

    public init() {}

    public func isCoolingDown(key: String, now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cooldowns[key] else { return false }
        return now.timeIntervalSince(entry.firedAt) < entry.duration
    }

    public func recordTrigger(key: String, duration: TimeInterval, now: Date) {
        lock.lock()
        defer { lock.unlock() }
        cooldowns[key] = (firedAt: now, duration: duration)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        cooldowns.removeAll()
    }
}
