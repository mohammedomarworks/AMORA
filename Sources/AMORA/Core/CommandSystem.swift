import AppKit
import Foundation
import Observation

enum AMORACommand: Equatable {
    case startTimer(duration: TimeInterval)
    case addTimerTime(duration: TimeInterval)
    case pauseTimer
    case resumeTimer
    case stopTimer
    case playMusic
    case pauseMusic
    case nextTrack
    case previousTrack
    case showBattery
    case showClipboard
    case showNotes
    case showFileShelf
    case showSystem
    case showDashboard
    case showSettings
    case createNote(text: String)
    case openApplication(name: String)
    case openFolder(name: String)
    case unknown(text: String)
}

enum AMORACommandResult: Equatable {
    case success(message: String)
    case failure(message: String)
    case needsInformation(prompt: String)
    case needsConfirmation(prompt: String)
    case unsupported(message: String)
}

struct AMORACommandContext: Equatable {
    var lastCommand: AMORACommand?
    var lastModule: String?
    var activeTimer = false
    var activeMedia = false
}

struct AMORACommandParser {
    func parse(_ input: String, context: AMORACommandContext = .init()) -> AMORACommand {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalize(original)
        guard !normalized.isEmpty else { return .unknown(text: "") }

        if let duration = duration(in: normalized), isTimerStart(normalized) {
            return .startTimer(duration: duration)
        }
        if isTimerStart(normalized) {
            return .unknown(text: normalized)
        }
        if let duration = duration(in: normalized), isAddTime(normalized) {
            return .addTimerTime(duration: duration)
        }

        if normalized == "pause" || normalized == "pause it" {
            if context.activeTimer { return .pauseTimer }
            if context.activeMedia { return .pauseMusic }
            return .unknown(text: normalized)
        }
        if normalized == "resume" || normalized == "resume it" {
            return context.activeTimer ? .resumeTimer : .unknown(text: normalized)
        }
        if normalized.contains("stop timer") || normalized == "stop it" || normalized == "cancel timer" {
            return .stopTimer
        }
        if normalized.contains("pause timer") { return .pauseTimer }
        if normalized.contains("resume timer") { return .resumeTimer }

        if normalized == "play" || normalized == "play music" || normalized == "start music" {
            return .playMusic
        }
        if normalized == "pause music" { return .pauseMusic }
        if normalized == "next" || normalized == "next song" || normalized == "next track" || normalized == "skip" {
            return .nextTrack
        }
        if normalized == "previous" || normalized == "previous song" || normalized == "previous track" {
            return .previousTrack
        }

        if isBatteryRequest(normalized) { return .showBattery }
        if normalized == "show clipboard" || normalized == "open clipboard" || normalized == "my clipboard" {
            return .showClipboard
        }
        if normalized == "show notes" || normalized == "open notes" { return .showNotes }
        if normalized == "show file shelf" || normalized == "open file shelf" || normalized == "file shelf" || normalized == "show files" || normalized == "pinned files" {
            return .showFileShelf
        }
        if isSystemRequest(normalized) { return .showSystem }
        if normalized == "open dashboard" || normalized == "show dashboard" || normalized == "dashboard" {
            return .showDashboard
        }
        if normalized == "open settings" || normalized == "show settings" || normalized == "settings" {
            return .showSettings
        }

        if let note = noteText(from: original, normalized: normalized) {
            return .createNote(text: note)
        }

        if let name = valueAfterOpen(normalized, prefix: "app") {
            return .openApplication(name: name)
        }
        if let name = valueAfterOpen(normalized, prefix: "application") {
            return .openApplication(name: name)
        }
        if let folder = folderName(from: normalized) { return .openFolder(name: folder) }
        if let app = applicationName(from: normalized) { return .openApplication(name: app) }

        return .unknown(text: normalized)
    }

    static func normalize(_ input: String) -> String {
        input.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func duration(in text: String) -> TimeInterval? {
        let pattern = #"\b(\d+(?:\.\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\b"#
        guard let match = text.range(of: pattern, options: .regularExpression) else {
            // The compact timer forms use minutes by convention: "timer 25".
            guard let number = text.split(separator: " ").last,
                  let value = Double(number), value > 0,
                  (text.hasPrefix("timer ") || text.hasPrefix("start timer ")) else { return nil }
            return validDuration(value * 60)
        }
        let valueText = text[match].split(whereSeparator: { $0.isWhitespace })
        guard let value = valueText.first.flatMap({ Double($0) }), value > 0,
              let unit = valueText.last else { return nil }
        let seconds: Double
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") || unit == "h" {
            seconds = value * 3600
        } else if unit.hasPrefix("second") || unit.hasPrefix("sec") || unit == "s" {
            seconds = value
        } else {
            seconds = value * 60
        }
        return validDuration(seconds)
    }

    private func validDuration(_ seconds: Double) -> TimeInterval? {
        guard seconds >= 1, seconds <= 24 * 60 * 60 else { return nil }
        return seconds.rounded()
    }

    private func isTimerStart(_ text: String) -> Bool {
        if text.hasPrefix("help") || text.contains("plan") || text.contains("how can") { return false }
        return text.contains("timer") || text.contains("focus session") || text.contains("pomodoro")
    }

    private func isAddTime(_ text: String) -> Bool {
        text.hasPrefix("add ") && (text.contains("minute") || text.contains("min ") || text.contains("second") || text.contains("hour"))
    }

    private func isBatteryRequest(_ text: String) -> Bool {
        if text.contains("improve") || text.contains("last longer") || text.contains("extend") || text.contains("life") { return false }
        return text == "battery" || text == "battery status" || text.contains("my battery") || text.contains("how much battery") || text == "am i charging"
    }

    private func isSystemRequest(_ text: String) -> Bool {
        text == "show system" || text == "system status" || text.contains("how is my mac") || text == "show cpu" || text == "show memory"
    }

    private func noteText(from original: String, normalized: String) -> String? {
        let patterns = ["^add a note\\s+", "^add note\\s+", "^save a note(?: that says)?\\s+", "^save note\\s+", "^make a note(?: saying)?\\s+"]
        for pattern in patterns {
            if let range = original.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let text = original[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func valueAfterOpen(_ text: String, prefix: String) -> String? {
        let marker = "open \(prefix) "
        guard text.hasPrefix(marker) else { return nil }
        let value = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func folderName(from text: String) -> String? {
        let allowed = ["downloads", "documents", "desktop"]
        guard text.hasPrefix("open ") else { return nil }
        let name = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return allowed.contains(name) ? name : nil
    }

    private func applicationName(from text: String) -> String? {
        guard text.hasPrefix("open ") else { return nil }
        let name = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        let allowed = ["safari", "finder", "terminal", "vs code"]
        return allowed.contains(name) ? name : nil
    }
}

@Observable @MainActor
final class AMORACommandHistory {
    static let shared = AMORACommandHistory()
    private(set) var items: [String] = []
    private let maximumCount = 10

    private init() {}

    func add(_ command: String) {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        items.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        items.insert(value, at: 0)
        if items.count > maximumCount { items.removeLast() }
    }

    func clear() { items.removeAll() }
}

@MainActor
final class AMORACommandRouter {
    static let shared = AMORACommandRouter()
    private(set) var context = AMORACommandContext()

    private init() {}

    func currentContext() -> AMORACommandContext {
        context.activeTimer = TimerService.shared.isRunning
        context.activeMedia = MusicService.shared.isPlaying
        return context
    }

    func execute(_ command: AMORACommand) -> AMORACommandResult {
        AMORAEventCenter.shared.emit(.commandProcessing)
        let result: AMORACommandResult
        switch command {
        case let .startTimer(duration):
            guard !TimerService.shared.isRunning else {
                result = .failure(message: "A timer is already running.")
                break
            }
            TimerService.shared.startTimer(seconds: Int(duration))
            context.lastModule = "timer"
            context.activeTimer = true
            result = .success(message: "Let's focus. \(Self.durationText(duration)) starts now.")
        case let .addTimerTime(duration):
            guard TimerService.shared.isRunning else {
                result = .needsInformation(prompt: "There isn't an active timer to extend.")
                break
            }
            TimerService.shared.addTime(seconds: Int(duration))
            result = .success(message: "Added \(Self.durationText(duration)) to the timer.")
        case .pauseTimer:
            guard TimerService.shared.isRunning, !TimerService.shared.isPaused else {
                result = .failure(message: "There isn't a running timer to pause.")
                break
            }
            TimerService.shared.pauseTimer()
            result = .success(message: "Timer paused.")
        case .resumeTimer:
            guard TimerService.shared.isPaused else {
                result = .failure(message: "There isn't a paused timer to resume.")
                break
            }
            TimerService.shared.resumeTimer()
            result = .success(message: "Back to it.")
        case .stopTimer:
            guard TimerService.shared.isRunning else {
                result = .failure(message: "There isn't an active timer.")
                break
            }
            TimerService.shared.stopTimer()
            context.activeTimer = false
            result = .success(message: "Timer stopped.")
        case .playMusic:
            MusicService.shared.play()
            context.lastModule = "music"
            context.activeMedia = true
            result = .success(message: "Music playing.")
        case .pauseMusic:
            MusicService.shared.pause()
            context.activeMedia = false
            result = .success(message: "Music paused.")
        case .nextTrack:
            MusicService.shared.nextTrack()
            result = .success(message: "Next track.")
        case .previousTrack:
            MusicService.shared.previousTrack()
            result = .success(message: "Previous track.")
        case .showBattery:
            BatteryService.shared.refresh()
            context.lastModule = "battery"
            result = .success(message: BatteryService.shared.hasBattery ? "Battery is at \(BatteryService.shared.level)%. \(BatteryService.shared.timeRemainingDescription.replacingOccurrences(of: "\n", with: " "))" : "This Mac doesn't report a battery.")
        case .showClipboard:
            WindowManager.shared.showDashboard(section: .clipboard)
            result = .success(message: "Here’s your clipboard.")
        case .showNotes:
            WindowManager.shared.showDashboard(section: .notes)
            result = .success(message: "Here are your notes.")
        case .showFileShelf:
            WindowManager.shared.showDashboard(section: .fileShelf)
            result = .success(message: "Here are your pinned files.")
        case .showSystem:
            SystemMonitorService.shared.refresh()
            WindowManager.shared.showDashboard(section: .overview)
            result = .success(message: String(format: "CPU is %.0f%%, with %.1f GB of memory in use.", SystemMonitorService.shared.cpuUsagePercent, SystemMonitorService.shared.memoryUsedGB))
        case .showDashboard:
            WindowManager.shared.showDashboard()
            result = .success(message: "Dashboard open.")
        case .showSettings:
            WindowManager.shared.showSettings()
            result = .success(message: "Settings open.")
        case let .createNote(text):
            NotesService.shared.addNote(text)
            context.lastModule = "notes"
            result = .success(message: "Saved.")
        case let .openApplication(name):
            result = openApplication(named: name)
        case let .openFolder(name):
            result = openFolder(named: name)
        case let .unknown(text):
            if text == "" {
                result = .needsInformation(prompt: "What should I do?")
            } else if text.contains("timer") || text.contains("focus session") || text.contains("pomodoro") {
                result = .needsInformation(prompt: "How long should I set it for?")
            } else if text == "open project" {
                result = .needsInformation(prompt: "Which project?")
            } else {
                result = .unsupported(message: "I don't know how to do that yet.")
            }
        }

        switch result {
        case .success: AMORAEventCenter.shared.emit(.commandSucceeded)
        case .failure, .unsupported, .needsInformation, .needsConfirmation: AMORAEventCenter.shared.emit(.commandFailed)
        }
        context.lastCommand = command
        return result
    }

    private func openApplication(named name: String) -> AMORACommandResult {
        let normalized = AMORACommandParser.normalize(name)
        let known: [String: String] = ["safari": "com.apple.Safari", "finder": "com.apple.finder", "terminal": "com.apple.Terminal", "vs code": "com.microsoft.VSCode"]
        guard let bundleID = known[normalized], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure(message: "I couldn't find that app.")
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return .success(message: "Opening \(name.capitalized).")
    }

    private func openFolder(named name: String) -> AMORACommandResult {
        let folders: [String: URL] = [
            "downloads": FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
            "documents": FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
            "desktop": FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        ]
        guard let url = folders[name], NSWorkspace.shared.open(url) else {
            return .failure(message: "I couldn't open that folder.")
        }
        return .success(message: "Opening \(name.capitalized).")
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds % 3600 == 0 { return "\(seconds / 3600) hour\(seconds == 3600 ? "" : "s")" }
        if seconds % 60 == 0 { return "\(seconds / 60) minute\(seconds == 60 ? "" : "s")" }
        return "\(seconds) seconds"
    }
}
