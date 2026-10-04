import AppKit
import Foundation

enum AMORATool: String, CaseIterable, Sendable { case battery, timer, music, browserMedia, notes, clipboard, file, fileShelf, system, application, folder, view }
enum AMORAToolOperation: Equatable, Sendable {
    case readBattery, startTimer(seconds: Int), pauseTimer, resumeTimer, stopTimer, addTimerTime(seconds: Int)
    case readMedia, playMedia, pauseMedia, nextTrack, previousTrack, createNote(text: String), listNotes
    case openApplication(name: String), openFolder(name: String), readSystem, showView(name: String)
}
enum AMORAToolSafety: String, Codable, Sendable { case readOnly, lowRisk, confirmationRequired }
struct AMORAToolRequest: Equatable, Sendable { let tool: AMORATool; let operation: AMORAToolOperation }
enum AMORAToolValidation: Equatable, Sendable { case allowed, needsConfirmation(prompt: String), rejected(reason: String) }
struct AMORAToolResult: Equatable, Sendable {
    enum Status: String, Sendable { case success, failure, unsupported, needsConfirmation, needsInformation }
    let tool: AMORATool; let status: Status; let message: String; let data: [String: String]; let executionID: UUID
    init(tool: AMORATool, status: Status, message: String, data: [String: String] = [:], executionID: UUID = UUID()) { self.tool = tool; self.status = status; self.message = message; self.data = data; self.executionID = executionID }
}

/// The only boundary through which model-generated actions can reach AMORA.
/// There is intentionally no shell, path, or arbitrary Swift invocation here.
@MainActor final class AMORAToolRegistry {
    static let shared = AMORAToolRegistry(); let maximumCallsPerRequest = 4
    private init() {}
    func execute(_ request: AMORAToolRequest, confirmed: Bool = false) -> AMORAToolResult {
        switch validate(request) {
        case .rejected(let reason): return .init(tool: request.tool, status: .failure, message: reason)
        case .needsConfirmation(let prompt) where !confirmed: return .init(tool: request.tool, status: .needsConfirmation, message: prompt)
        case .allowed, .needsConfirmation: return perform(request)
        }
    }
    func validate(_ request: AMORAToolRequest) -> AMORAToolValidation {
        switch request.operation {
        case .readBattery, .readMedia, .readSystem, .listNotes: return .allowed
        case let .startTimer(seconds), let .addTimerTime(seconds): return (1...86_400).contains(seconds) ? .allowed : .rejected(reason: "Timer duration is outside the supported range.")
        case .pauseTimer, .resumeTimer, .stopTimer, .playMedia, .pauseMedia, .nextTrack, .previousTrack, .createNote, .openApplication, .showView: return .allowed
        case let .openFolder(name): return Self.folderURL(name) == nil ? .rejected(reason: "That folder is not available through AMORA.") : .needsConfirmation(prompt: "Would you like me to open \(name.capitalized)?")
        }
    }
    private func perform(_ request: AMORAToolRequest) -> AMORAToolResult {
        switch request.operation {
        case .readBattery:
            BatteryService.shared.refresh(); guard BatteryService.shared.hasBattery else { return .init(tool: .battery, status: .unsupported, message: "This Mac doesn't report a battery.") }
            let estimate = BatteryService.shared.timeRemainingDescription.replacingOccurrences(of: "\n", with: " ")
            return .init(tool: .battery, status: .success, message: "Battery is at \(BatteryService.shared.level)%. \(estimate)", data: ["percentage": "\(BatteryService.shared.level)", "charging": BatteryService.shared.isCharging ? "true" : "false", "estimate": estimate])
        case let .startTimer(seconds):
            guard !TimerService.shared.isRunning else { return .init(tool: .timer, status: .failure, message: "A timer is already running.") }; TimerService.shared.startTimer(seconds: seconds); return .init(tool: .timer, status: .success, message: "Your timer is running for \(Self.durationText(seconds)).")
        case .pauseTimer:
            guard TimerService.shared.isRunning, !TimerService.shared.isPaused else { return .init(tool: .timer, status: .failure, message: "There isn't a running timer to pause.") }; TimerService.shared.pauseTimer(); return .init(tool: .timer, status: .success, message: "Timer paused.")
        case .resumeTimer: guard TimerService.shared.isPaused else { return .init(tool: .timer, status: .failure, message: "There isn't a paused timer to resume.") }; TimerService.shared.resumeTimer(); return .init(tool: .timer, status: .success, message: "Timer resumed.")
        case .stopTimer: guard TimerService.shared.isRunning else { return .init(tool: .timer, status: .failure, message: "There isn't an active timer.") }; TimerService.shared.stopTimer(); return .init(tool: .timer, status: .success, message: "Timer stopped.")
        case let .addTimerTime(seconds): guard TimerService.shared.isRunning else { return .init(tool: .timer, status: .needsInformation, message: "There isn't an active timer to extend.") }; TimerService.shared.addTime(seconds: seconds); return .init(tool: .timer, status: .success, message: "Added \(Self.durationText(seconds)) to the timer.")
        case .readMedia:
            MusicService.shared.checkCurrentTrack(); guard MusicService.shared.isAvailable else { return .init(tool: .music, status: .unsupported, message: "I couldn't find active media.") }
            let source = MusicService.shared.source == .youtube ? "YouTube" : "Music"; let title = MusicService.shared.trackTitle
            return .init(tool: .music, status: .success, message: "\(MusicService.shared.isPlaying ? "Playing" : "Paused"): \(title) on \(source).", data: ["title": title, "source": source, "playing": MusicService.shared.isPlaying ? "true" : "false"])
        case .playMedia: return mediaControl(playing: true)
        case .pauseMedia: return mediaControl(playing: false)
        case .nextTrack: MusicService.shared.nextTrack(); return .init(tool: .music, status: .success, message: "Playing the next track.")
        case .previousTrack: MusicService.shared.previousTrack(); return .init(tool: .music, status: .success, message: "Playing the previous track.")
        case let .createNote(text): guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .init(tool: .notes, status: .needsInformation, message: "What should I save?") }; NotesService.shared.addNote(text); return .init(tool: .notes, status: .success, message: "Saved.")
        case .listNotes: return .init(tool: .notes, status: .success, message: NotesService.shared.notes.isEmpty ? "You don't have any notes yet." : "You have \(NotesService.shared.notes.count) saved notes.", data: ["count": "\(NotesService.shared.notes.count)"])
        case let .openApplication(name):
            let ids = ["safari": "com.apple.Safari", "finder": "com.apple.finder", "terminal": "com.apple.Terminal", "vs code": "com.microsoft.VSCode"]; guard let id = ids[AMORACommandParser.normalize(name)], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return .init(tool: .application, status: .failure, message: "I couldn't find that app.") }; NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()); return .init(tool: .application, status: .success, message: "Opening \(name.capitalized).")
        case let .openFolder(name): guard let url = Self.folderURL(name), NSWorkspace.shared.open(url) else { return .init(tool: .folder, status: .failure, message: "I couldn't open that folder.") }; return .init(tool: .folder, status: .success, message: "Opening \(name.capitalized).")
        case .readSystem: SystemMonitorService.shared.refresh(); let s = SystemMonitorService.shared; return .init(tool: .system, status: .success, message: String(format: "CPU is %.0f%%, with %.1f GB of memory in use.", s.cpuUsagePercent, s.memoryUsedGB), data: ["cpu": "\(s.cpuUsagePercent)", "memoryGB": "\(s.memoryUsedGB)"])
        case let .showView(name):
            switch AMORACommandParser.normalize(name) { case "dashboard", "controls": WindowManager.shared.showDashboard(); case "notes": WindowManager.shared.showDashboard(section: .notes); case "clipboard": WindowManager.shared.showDashboard(section: .clipboard); case "files", "fileshelf", "file shelf", "shelf": WindowManager.shared.showDashboard(section: .fileShelf); case "settings": WindowManager.shared.showSettings(); default: return .init(tool: .view, status: .failure, message: "That AMORA view is not available.") }; return .init(tool: .view, status: .success, message: "Showing \(name).")
        }
    }
    private func mediaControl(playing: Bool) -> AMORAToolResult {
        MusicService.shared.checkCurrentTrack(); guard MusicService.shared.isAvailable else { return .init(tool: .music, status: .unsupported, message: "No supported media is available.") }; guard MusicService.shared.isPlaying != playing else { return .init(tool: .music, status: .success, message: playing ? "Media is already playing." : "Media is already paused.") }; if playing { MusicService.shared.play() } else { MusicService.shared.pause() }; return .init(tool: MusicService.shared.source == .youtube ? .browserMedia : .music, status: .success, message: playing ? "Media is playing." : "Media is paused.")
    }
    private static func folderURL(_ name: String) -> URL? { let folders: [String: FileManager.SearchPathDirectory] = ["downloads": .downloadsDirectory, "documents": .documentDirectory, "desktop": .desktopDirectory]; guard let directory = folders[AMORACommandParser.normalize(name)] else { return nil }; return FileManager.default.urls(for: directory, in: .userDomainMask).first }
    private static func durationText(_ seconds: Int) -> String { if seconds % 3600 == 0 { return "\(seconds / 3600) hour\(seconds == 3600 ? "" : "s")" }; if seconds % 60 == 0 { return "\(seconds / 60) minute\(seconds == 60 ? "" : "s")" }; return "\(seconds) seconds" }
}

struct AMORAToolValidator: Sendable { @MainActor func validate(_ request: AMORAToolRequest) -> AMORAToolValidation { AMORAToolRegistry.shared.validate(request) } }

/// Provider-neutral, strict JSON envelope. Providers may return ordinary prose;
/// only this exact envelope can request local actions.
struct AMORAToolPlan: Codable, Sendable {
    struct Call: Codable, Sendable {
        let tool: String
        let action: String
        let seconds: Int?
        let text: String?
        let name: String?
    }
    let calls: [Call]

    @MainActor func requests() -> [AMORAToolRequest]? {
        guard !calls.isEmpty, calls.count <= AMORAToolRegistry.shared.maximumCallsPerRequest else { return nil }
        let requests: [AMORAToolRequest] = calls.compactMap { (call) -> AMORAToolRequest? in
            guard let tool = AMORATool.allCases.first(where: { $0.rawValue.lowercased() == call.tool.lowercased() }) else { return nil }
            switch (tool, call.action.lowercased()) {
            case (.battery, "read"): return .init(tool: tool, operation: .readBattery)
            case (.timer, "start"): return call.seconds.map { .init(tool: tool, operation: .startTimer(seconds: $0)) }
            case (.timer, "pause"): return .init(tool: tool, operation: .pauseTimer)
            case (.timer, "resume"): return .init(tool: tool, operation: .resumeTimer)
            case (.timer, "stop"): return .init(tool: tool, operation: .stopTimer)
            case (.timer, "add"): return call.seconds.map { .init(tool: tool, operation: .addTimerTime(seconds: $0)) }
            case (.music, "read"), (.browserMedia, "read"): return .init(tool: tool, operation: .readMedia)
            case (.music, "play"), (.browserMedia, "play"): return .init(tool: tool, operation: .playMedia)
            case (.music, "pause"), (.browserMedia, "pause"): return .init(tool: tool, operation: .pauseMedia)
            case (.music, "next"): return .init(tool: tool, operation: .nextTrack)
            case (.music, "previous"): return .init(tool: tool, operation: .previousTrack)
            case (.notes, "create"): return call.text.map { .init(tool: tool, operation: .createNote(text: $0)) }
            case (.notes, "list"): return .init(tool: tool, operation: .listNotes)
            case (.application, "open"): return call.name.map { .init(tool: tool, operation: .openApplication(name: $0)) }
            case (.folder, "open"): return call.name.map { .init(tool: tool, operation: .openFolder(name: $0)) }
            case (.system, "read"): return .init(tool: tool, operation: .readSystem)
            case (.view, "show"): return call.name.map { .init(tool: tool, operation: .showView(name: $0)) }
            default: return nil
            }
        }
        return requests.count == calls.count ? requests : nil
    }
}
