import Foundation

/// Events are the only cross-service path into AMORA's personality layer.
/// Producers stay unaware of expressions, sounds, and island presentation.
public enum AMORAEvent: String, CaseIterable, Equatable, Sendable {
    case launched, opened, closed
    case timerStarted, timerPaused, timerResumed, timerNearlyFinished, timerCompleted
    case charging, chargedFull, lowBattery, criticalBattery
    case musicStarted, musicPaused, musicChanged, musicStopped
    case clipboardUpdated, clipboardRestored, noteCreated, fileReceived
    case commandProcessing, commandSucceeded, commandFailed
    case aiThinking, aiSucceeded, aiFailed, aiCancelled
    case proactiveSuggestionPresented, proactiveSuggestionDismissed
    case automationNotificationPresented, automationNotificationDismissed
    case systemIdle, systemActive
}

/// Cross-platform event-sink protocol for emitting high-level application events
/// without direct coupling to AppKit, UI windows, or platform-specific presentation services.
@MainActor
public protocol AmoraEventSinking: Sendable {
    func emit(_ event: AMORAEvent)
}

/// Default platform event sink that forwards events to `AMORAEventCenter.shared`.
@MainActor
public struct MacOSAmoraEventSink: AmoraEventSinking {
    public init() {}

    public func emit(_ event: AMORAEvent) {
        AMORAEventCenter.shared.emit(event)
    }
}

/// A thread-safe, recording event sink for deterministic testing without UI side effects.
@MainActor
public final class MockAmoraEventSink: AmoraEventSinking {
    public private(set) var recordedEvents: [AMORAEvent] = []

    public init() {}

    public func emit(_ event: AMORAEvent) {
        recordedEvents.append(event)
    }

    public var count: Int {
        recordedEvents.count
    }

    public func contains(_ event: AMORAEvent) -> Bool {
        recordedEvents.contains(event)
    }

    public func lastEvent() -> AMORAEvent? {
        recordedEvents.last
    }

    public func reset() {
        recordedEvents.removeAll()
    }
}
