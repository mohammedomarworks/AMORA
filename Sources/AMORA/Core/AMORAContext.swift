import Foundation
import Observation

/// The small, local-only snapshot AMORA uses to understand what is happening
/// right now. This intentionally contains state, not user content or history.
@Observable @MainActor
final class AMORAContext {
    static let shared = AMORAContext()

    var batteryLevel: Int?
    var isCharging = false
    var timerRemainingSeconds = 0
    var timerIsRunning = false
    var timerIsPaused = false
    var musicTitle = ""
    var musicArtist = ""
    var musicIsPlaying = false
    var activeModule: DynamicIslandMode = .normal
    var isAMORAExpanded = false
    var isUserInteracting = false
    var isSystemIdle = false
    var lastAction: String?
    var currentEvent: AMORAEvent?
    var currentEventDate: Date?
    var lastInteractionDate: Date?
    var assistantState: AssistantState = .idle
    var displayName: String?
    private var isRefreshing = false

    private init() {}

    func refreshFromServices() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let battery = BatteryService.shared
        batteryLevel = battery.hasBattery ? battery.level : nil
        isCharging = battery.isCharging

        let timer = TimerService.shared
        timerRemainingSeconds = timer.remainingSeconds
        timerIsRunning = timer.isRunning
        timerIsPaused = timer.isPaused

        let music = MusicService.shared
        musicTitle = music.trackTitle
        musicArtist = music.artist
        musicIsPlaying = music.isPlaying
        activeModule = IslandActivityCenter.shared.mode
        isAMORAExpanded = IslandModel.shared.isExpanded
    }

    func record(_ event: AMORAEvent) {
        currentEvent = event
        currentEventDate = Date()

        switch event {
        case .opened:
            isUserInteracting = true
            isAMORAExpanded = true
            lastInteractionDate = Date()
        case .closed:
            isUserInteracting = false
            isAMORAExpanded = false
        case .timerStarted, .timerPaused, .timerResumed, .timerCompleted:
            lastAction = "timer"
        case .musicStarted, .musicPaused, .musicChanged, .musicStopped:
            lastAction = "music"
        case .clipboardUpdated, .clipboardRestored:
            lastAction = "clipboard"
        case .noteCreated:
            lastAction = "note"
        case .fileReceived:
            lastAction = "file"
        case .commandProcessing, .commandSucceeded, .commandFailed:
            lastAction = "command"
        case .aiThinking:
            lastAction = "assistant"
            assistantState = .thinking
        case .aiSucceeded:
            lastAction = "assistant"
            assistantState = .responding
        case .aiFailed:
            lastAction = "assistant"
            assistantState = .failed
        case .aiCancelled:
            lastAction = "assistant"
            assistantState = .cancelled
        default:
            break
        }
    }

    func beginInteraction() {
        isUserInteracting = true
        lastInteractionDate = Date()
    }

    func endInteraction() {
        isUserInteracting = false
        lastInteractionDate = Date()
    }

}

/// Events are the only cross-service path into AMORA's personality layer.
/// Producers stay unaware of expressions, sounds, and island presentation.
enum AMORAEvent: Equatable {
    case launched, opened, closed
    case timerStarted, timerPaused, timerResumed, timerCompleted
    case charging, chargedFull, lowBattery, criticalBattery
    case musicStarted, musicPaused, musicChanged, musicStopped
    case clipboardUpdated, clipboardRestored, noteCreated, fileReceived
    case commandProcessing, commandSucceeded, commandFailed
    case aiThinking, aiSucceeded, aiFailed, aiCancelled
    case systemIdle, systemActive
}

@MainActor
final class AMORAEventCenter {
    static let shared = AMORAEventCenter()

    private init() {}

    func emit(_ event: AMORAEvent) {
        AMORAContext.shared.record(event)
        PersonalityEngine.shared.react(to: event)
    }
}
