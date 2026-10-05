import Foundation

struct AIConversation: Sendable {
    let id = UUID()
    private(set) var messages: [AIMessage] = []
    private let maximumMessages = 12

    mutating func append(_ message: AIMessage) {
        messages.append(message)
        if messages.count > maximumMessages {
            messages.removeFirst(messages.count - maximumMessages)
        }
    }

    mutating func reset() { messages.removeAll() }
}

enum AIContextComposer {
    /// Only attach facts that are clearly relevant to the request.
    @MainActor static func relevantContext(for input: String) -> String? {
        let normalized = AMORACommandParser.normalize(input)
        var facts: [String] = []
        if normalized.contains("battery") {
            let battery = BatteryService.shared
            if battery.hasBattery { facts.append("Current battery: \(battery.level)%\(battery.isCharging ? ", charging" : "")") }
        }
        if normalized.contains("timer") || normalized.contains("study") || normalized.contains("focus") {
            let timer = TimerService.shared
            if timer.isRunning { facts.append("Active timer: \(timer.remainingSeconds) seconds remaining\(timer.isPaused ? ", paused" : "")") }
        }
        if normalized.contains("music") || normalized.contains("song") || normalized.contains("track") || normalized.contains("spotify") {
            let music = MusicService.shared
            if !music.trackTitle.isEmpty { facts.append("Current music: \(music.trackTitle) by \(music.artist) on \(music.source.displayName)") }
        }
        return facts.isEmpty ? nil : "Relevant local context (use only if helpful):\n" + facts.joined(separator: "\n")
    }
}
