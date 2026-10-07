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
    case playSpotify
    case pauseSpotify
    case nextSpotify
    case previousSpotify
    case playAppleMusic
    case pauseAppleMusic
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

        if isTimerCancel(normalized) {
            return .stopTimer
        }
        if isTimerPause(normalized) {
            return .pauseTimer
        }
        if isTimerResume(normalized) {
            return .resumeTimer
        }

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

        if normalized == "play spotify" || normalized == "start spotify" || normalized == "resume spotify" {
            return .playSpotify
        }
        if normalized == "pause spotify" || normalized == "stop spotify" {
            return .pauseSpotify
        }
        if normalized == "next spotify" || normalized == "skip spotify" || normalized == "next song spotify" || normalized == "next track spotify" || normalized == "next song on spotify" || normalized == "next track on spotify" {
            return .nextSpotify
        }
        if normalized == "previous spotify" || normalized == "previous song spotify" || normalized == "previous track spotify" || normalized == "previous song on spotify" || normalized == "previous track on spotify" {
            return .previousSpotify
        }
        if normalized == "play apple music" || normalized == "start apple music" {
            return .playAppleMusic
        }
        if normalized == "pause apple music" || normalized == "stop apple music" {
            return .pauseAppleMusic
        }

        if normalized == "play" || normalized == "play music" || normalized == "start music" || normalized == "play the music" || normalized == "resume music" {
            return .playMusic
        }
        if normalized == "pause music" || normalized == "pause the music" || normalized == "stop music" {
            return .pauseMusic
        }
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
        if normalized == "open dashboard" || normalized == "show dashboard" || normalized == "dashboard" || normalized == "open workspace" || normalized == "show workspace" || normalized == "workspace" {
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

    private func isTimerCancel(_ text: String) -> Bool {
        let cancelPatterns = [
            "cancel the timer", "cancel my timer", "cancel timer",
            "stop the timer", "stop my timer", "stop timer",
            "end the timer", "end my timer", "end timer",
            "turn off the timer", "turn off my timer", "turn off timer",
            "clear the timer", "clear my timer", "clear timer",
            "stop it", "cancel it", "turn it off"
        ]
        return cancelPatterns.contains { text.contains($0) || text == $0 }
    }

    private func isTimerPause(_ text: String) -> Bool {
        let pausePatterns = ["pause the timer", "pause my timer", "pause timer"]
        return pausePatterns.contains { text.contains($0) || text == $0 }
    }

    private func isTimerResume(_ text: String) -> Bool {
        let resumePatterns = ["resume the timer", "resume my timer", "resume timer"]
        return resumePatterns.contains { text.contains($0) || text == $0 }
    }

    private func isTimerStart(_ text: String) -> Bool {
        if text.hasPrefix("help") || text.contains("plan") || text.contains("how can") { return false }
        if isTimerCancel(text) || isTimerPause(text) || isTimerResume(text) { return false }
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
        let target: String
        if text.hasPrefix("open ") {
            target = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if text.hasPrefix("show ") {
            target = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        switch target {
        case "downloads", "download": return "downloads"
        case "documents", "document", "docs": return "documents"
        case "desktop": return "desktop"
        case "home": return "home"
        default: return nil
        }
    }

    private func applicationName(from text: String) -> String? {
        guard text.hasPrefix("open ") else { return nil }
        let name = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        let forbidden = ["downloads", "documents", "desktop", "home", "dashboard", "settings", "clipboard", "notes", "file shelf", "workspace"]
        if forbidden.contains(name) { return nil }
        return name.isEmpty ? nil : name
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
            let coordinator = AmoraActionExecutionCoordinator.shared
            coordinator.beginSequence([.startTimer(duration: duration)])
            coordinator.willExecuteItem(at: 0)
            TimerService.shared.startTimer(seconds: Int(duration))
            context.lastModule = "timer"
            context.activeTimer = true
            let msg = "Let's focus. \(Self.durationText(duration)) starts now."
            let successRes = AmoraActionResult.success(actionId: "timer.start", message: msg)
            coordinator.didCompleteItem(at: 0, result: successRes)
            coordinator.finishSequence(results: [successRes])
            result = .success(message: msg)
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
                result = .failure(message: "I don't see an active timer. Would you like to start one?")
                break
            }
            let coordinator = AmoraActionExecutionCoordinator.shared
            coordinator.beginSequence([.cancelTimer])
            coordinator.willExecuteItem(at: 0)
            TimerService.shared.stopTimer()
            context.activeTimer = false
            let msg = "Timer stopped."
            let successRes = AmoraActionResult.success(actionId: "timer.cancel", message: msg)
            coordinator.didCompleteItem(at: 0, result: successRes)
            coordinator.finishSequence(results: [successRes])
            result = .success(message: msg)
        case .playSpotify:
            guard SpotifyProvider.shared.isInstalled else {
                result = .failure(message: "Spotify is not installed on this Mac.")
                break
            }
            if SpotifyProvider.shared.hasPermissionDenied {
                result = .failure(message: "AMORA needs Automation permission to control Spotify. You can enable it in System Settings > Privacy & Security > Automation.")
                break
            }
            let coordinator = AmoraActionExecutionCoordinator.shared
            coordinator.beginSequence([.playMusic])
            coordinator.willExecuteItem(at: 0)
            MusicService.shared.play(preferredSource: .spotify)
            context.lastModule = "music"
            context.activeMedia = true
            let msg = "Spotify playing."
            let successRes = AmoraActionResult.success(actionId: "media.play", message: msg)
            coordinator.didCompleteItem(at: 0, result: successRes)
            coordinator.finishSequence(results: [successRes])
            result = .success(message: msg)
        case .pauseSpotify:
            guard SpotifyProvider.shared.isRunning else {
                result = .failure(message: "Spotify is not running.")
                break
            }
            MusicService.shared.pause(preferredSource: .spotify)
            context.activeMedia = false
            result = .success(message: "Spotify paused.")
        case .nextSpotify:
            guard SpotifyProvider.shared.isRunning else {
                result = .failure(message: "Spotify is not running.")
                break
            }
            MusicService.shared.nextTrack(preferredSource: .spotify)
            result = .success(message: "Next track on Spotify.")
        case .previousSpotify:
            guard SpotifyProvider.shared.isRunning else {
                result = .failure(message: "Spotify is not running.")
                break
            }
            MusicService.shared.previousTrack(preferredSource: .spotify)
            result = .success(message: "Previous track on Spotify.")
        case .playAppleMusic:
            MusicService.shared.play(preferredSource: .appleMusic)
            context.lastModule = "music"
            context.activeMedia = true
            result = .success(message: "Apple Music playing.")
        case .pauseAppleMusic:
            MusicService.shared.pause(preferredSource: .appleMusic)
            context.activeMedia = false
            result = .success(message: "Apple Music paused.")
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
                if text.contains("cancel") || text.contains("stop") || text.contains("end") || text.contains("turn off") || text.contains("clear") {
                    result = .failure(message: "I don't see an active timer. Would you like to start one?")
                } else {
                    result = .needsInformation(prompt: "How long should I set it for?")
                }
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
        let coordinator = AmoraActionExecutionCoordinator.shared
        coordinator.beginSequence([.openApplication(name: name)])
        coordinator.willExecuteItem(at: 0)

        let launcher = NativeAmoraApplicationLauncher()
        guard let url = launcher.resolveApplicationURL(named: name) else {
            let res = AmoraActionResult.unavailable(actionId: "app.open", message: "I couldn't find that app.")
            coordinator.didFailItem(at: 0, result: res)
            coordinator.finishSequence(results: [res])
            return .failure(message: "I couldn't find that app.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let successRes = AmoraActionResult.success(actionId: "app.open", message: "Opening \(name.capitalized).")
        coordinator.didCompleteItem(at: 0, result: successRes)
        coordinator.finishSequence(results: [successRes])
        return .success(message: "Opening \(name.capitalized).")
    }

    private func openFolder(named name: String) -> AMORACommandResult {
        let coordinator = AmoraActionExecutionCoordinator.shared
        coordinator.beginSequence([.openFolder(location: name)])
        coordinator.willExecuteItem(at: 0)

        let opener = NativeAmoraFolderOpener()
        guard let url = opener.resolveFolderURL(for: name), NSWorkspace.shared.open(url) else {
            let res = AmoraActionResult.unavailable(actionId: "folder.open", message: "I couldn't open that folder.")
            coordinator.didFailItem(at: 0, result: res)
            coordinator.finishSequence(results: [res])
            return .failure(message: "I couldn't open that folder.")
        }
        let successRes = AmoraActionResult.success(actionId: "folder.open", message: "Opening \(name.capitalized).")
        coordinator.didCompleteItem(at: 0, result: successRes)
        coordinator.finishSequence(results: [successRes])
        return .success(message: "Opening \(name.capitalized).")
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds % 3600 == 0 { return "\(seconds / 3600) hour\(seconds == 3600 ? "" : "s")" }
        if seconds % 60 == 0 { return "\(seconds / 60) minute\(seconds == 60 ? "" : "s")" }
        return "\(seconds) seconds"
    }
}
