import Foundation

enum AMORATool: String, CaseIterable, Sendable { case battery, timer, music, browserMedia, notes, clipboard, file, fileShelf, system, application, folder, view, memory }
enum AMORAToolOperation: Equatable, Sendable {
    case readBattery, startTimer(seconds: Int), pauseTimer, resumeTimer, stopTimer, addTimerTime(seconds: Int)
    case readMedia, playMedia, pauseMedia, nextTrack, previousTrack, createNote(text: String), listNotes, searchNotes(query: String)
    case openApplication(name: String), openFolder(name: String), readSystem, showView(name: String)
    case saveMemory(key: String, value: String), recallMemory(query: String), listMemories, forgetMemory(query: String), updateMemory(key: String, value: String), clearMemories(confirmed: Bool)
    case listShelfFiles, openShelfFile(name: String), revealShelfFile(name: String), removeShelfFile(name: String), clearShelfFiles(confirmed: Bool)
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
    static var isControlledEvaluationMode = false
    public var appLauncher: any AmoraApplicationLaunching = NativeAmoraApplicationLauncher()
    public var folderOpener: any AmoraFolderOpening = NativeAmoraFolderOpener()
    private init() {}
    func execute(_ request: AMORAToolRequest, confirmed: Bool = false) async -> AMORAToolResult {
        switch validate(request) {
        case .rejected(let reason): return .init(tool: request.tool, status: .failure, message: reason)
        case .needsConfirmation(let prompt) where !confirmed: return .init(tool: request.tool, status: .needsConfirmation, message: prompt)
        case .allowed, .needsConfirmation: return await perform(request)
        }
    }
    func validate(_ request: AMORAToolRequest) -> AMORAToolValidation {
        switch request.operation {
        case .readBattery, .readMedia, .readSystem, .listNotes, .searchNotes, .recallMemory, .listMemories, .forgetMemory, .listShelfFiles, .openShelfFile, .revealShelfFile, .removeShelfFile: return .allowed
        case let .startTimer(seconds), let .addTimerTime(seconds): return (1...86_400).contains(seconds) ? .allowed : .rejected(reason: "Timer duration is outside the supported range.")
        case .pauseTimer, .resumeTimer, .stopTimer, .playMedia, .pauseMedia, .nextTrack, .previousTrack, .createNote, .openApplication, .showView: return .allowed
        case let .openFolder(name): return folderOpener.resolveFolderURL(for: name) == nil ? .rejected(reason: "That folder is not available through AMORA.") : .needsConfirmation(prompt: "Would you like me to open \(name.capitalized)?")
        case let .saveMemory(key, value):
            let result = AmoraMemoryPrivacyValidator.shared.validate(key: key, value: value)
            switch result {
            case .allowed: return .allowed
            case .rejected(let reason): return .rejected(reason: reason)
            }
        case let .updateMemory(key, value):
            let result = AmoraMemoryPrivacyValidator.shared.validate(key: key, value: value)
            switch result {
            case .allowed: return .allowed
            case .rejected(let reason): return .rejected(reason: reason)
            }
        case .clearMemories(let confirmed):
            return confirmed ? .allowed : .needsConfirmation(prompt: "Are you sure you want me to forget everything? This will permanently delete all stored memories.")
        case .clearShelfFiles(let confirmed):
            return confirmed ? .allowed : .needsConfirmation(prompt: "Are you sure you want to clear your File Shelf? (This will not delete the original files from your Mac.)")
        }
    }
    private func perform(_ request: AMORAToolRequest) async -> AMORAToolResult {
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
            let source = MusicService.shared.source.displayName; let title = MusicService.shared.trackTitle
            return .init(tool: .music, status: .success, message: "\(MusicService.shared.isPlaying ? "Playing" : "Paused"): \(title) on \(source).", data: ["title": title, "source": source, "playing": MusicService.shared.isPlaying ? "true" : "false"])
        case .playMedia: return mediaControl(playing: true)
        case .pauseMedia: return mediaControl(playing: false)
        case .nextTrack: MusicService.shared.nextTrack(); return .init(tool: .music, status: .success, message: "Playing the next track.")
        case .previousTrack: MusicService.shared.previousTrack(); return .init(tool: .music, status: .success, message: "Playing the previous track.")
        case let .createNote(text): guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .init(tool: .notes, status: .needsInformation, message: "What should I save?") }; NotesService.shared.addNote(text); return .init(tool: .notes, status: .success, message: "Saved.")
        case .listNotes: return .init(tool: .notes, status: .success, message: NotesService.shared.notes.isEmpty ? "You don't have any notes yet." : "You have \(NotesService.shared.notes.count) saved notes.", data: ["count": "\(NotesService.shared.notes.count)"])
        case let .searchNotes(query):
            let results = NotesService.shared.searchNotes(query: query)
            if results.isEmpty {
                return .init(tool: .notes, status: .success, message: "No notes found matching '\(query)'.", data: ["count": "0", "query": query])
            }
            let list = results.prefix(5).map { "• \($0.text)" }.joined(separator: "\n")
            let countMsg = results.count == 1 ? "1 matching note" : "\(results.count) matching notes"
            return .init(tool: .notes, status: .success, message: "Found \(countMsg):\n\(list)", data: ["count": "\(results.count)", "query": query])
        case let .openApplication(name):
            guard let url = appLauncher.resolveApplicationURL(named: name) else { return .init(tool: .application, status: .failure, message: "I couldn't find that app.") }
            if !Self.isControlledEvaluationMode { _ = try? await appLauncher.openApplication(at: url) }
            return .init(tool: .application, status: .success, message: "Opening \(name.capitalized).")
        case let .openFolder(name):
            guard let url = folderOpener.resolveFolderURL(for: name) else { return .init(tool: .folder, status: .failure, message: "I couldn't open that folder.") }
            if !Self.isControlledEvaluationMode {
                do {
                    try await folderOpener.openFolder(at: url)
                } catch {
                    return .init(tool: .folder, status: .failure, message: "I couldn't open that folder.")
                }
            }
            return .init(tool: .folder, status: .success, message: "Opening \(name.capitalized).")
        case .readSystem: SystemMonitorService.shared.refresh(); let s = SystemMonitorService.shared; return .init(tool: .system, status: .success, message: String(format: "CPU is %.0f%%, with %.1f GB of memory in use.", s.cpuUsagePercent, s.memoryUsedGB), data: ["cpu": "\(s.cpuUsagePercent)", "memoryGB": "\(s.memoryUsedGB)"])
        case let .showView(name):
            switch AMORACommandParser.normalize(name) { case "dashboard", "controls": WindowManager.shared.showDashboard(); case "notes": WindowManager.shared.showDashboard(section: .notes); case "clipboard": WindowManager.shared.showDashboard(section: .clipboard); case "files", "fileshelf", "file shelf", "shelf": WindowManager.shared.showDashboard(section: .fileShelf); case "settings": WindowManager.shared.showSettings(); default: return .init(tool: .view, status: .failure, message: "That AMORA view is not available.") }; return .init(tool: .view, status: .success, message: "Showing \(name).")
        case let .saveMemory(key, value):
            let store = AssistantManager.shared.memoryStore
            do {
                let saved = try await store.save(key: key, value: value)
                await AmoraMemoryService.shared.refresh()
                return .init(tool: .memory, status: .success, message: "I'll remember that \(saved.key): \(saved.value).", data: ["key": saved.key, "value": saved.value, "id": saved.id.uuidString])
            } catch {
                return .init(tool: .memory, status: .failure, message: "Failed to save memory: \(error.localizedDescription)")
            }
        case let .recallMemory(query):
            let store = AssistantManager.shared.memoryStore
            let results = await store.search(query: query)
            if results.isEmpty {
                return .init(tool: .memory, status: .success, message: "No memories found matching '\(query)'.", data: ["count": "0", "query": query])
            }
            let list = results.prefix(5).map { "• \($0.key): \($0.value)" }.joined(separator: "\n")
            let countStr = results.count == 1 ? "1 matching memory" : "\(results.count) matching memories"
            return .init(tool: .memory, status: .success, message: "Found \(countStr):\n\(list)", data: ["count": "\(results.count)", "query": query])
        case .listMemories:
            let store = AssistantManager.shared.memoryStore
            let memories = await store.list()
            if memories.isEmpty {
                return .init(tool: .memory, status: .success, message: "You don't have any memories stored yet.", data: ["count": "0"])
            }
            let list = memories.map { "• \($0.key): \($0.value)" }.joined(separator: "\n")
            return .init(tool: .memory, status: .success, message: "Here are your saved memories:\n\(list)", data: ["count": "\(memories.count)"])
        case let .forgetMemory(query):
            let store = AssistantManager.shared.memoryStore
            do {
                let deleted = try await store.deleteMatching(query: query)
                if deleted.isEmpty {
                    return .init(tool: .memory, status: .success, message: "I don't have a memory matching that.", data: ["count": "0"])
                }
                await AmoraMemoryService.shared.refresh()
                let names = deleted.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                return .init(tool: .memory, status: .success, message: "I've forgotten that: \(names).", data: ["count": "\(deleted.count)"])
            } catch {
                return .init(tool: .memory, status: .failure, message: "Failed to delete memory: \(error.localizedDescription)")
            }
        case let .updateMemory(key, value):
            let store = AssistantManager.shared.memoryStore
            do {
                if let updated = try await store.updateMatching(query: key, newValue: value, newKey: nil) {
                    await AmoraMemoryService.shared.refresh()
                    return .init(tool: .memory, status: .success, message: "I've updated your \(updated.key) to: \(updated.value).", data: ["key": updated.key, "value": updated.value, "id": updated.id.uuidString])
                } else {
                    let saved = try await store.save(key: key, value: value)
                    await AmoraMemoryService.shared.refresh()
                    return .init(tool: .memory, status: .success, message: "I didn't find an existing memory matching that, so I remembered that \(saved.key): \(saved.value).", data: ["key": saved.key, "value": saved.value, "id": saved.id.uuidString])
                }
            } catch {
                return .init(tool: .memory, status: .failure, message: "Failed to update memory: \(error.localizedDescription)")
            }
        case let .clearMemories(confirmed):
            guard confirmed else {
                return .init(tool: .memory, status: .needsConfirmation, message: "Are you sure you want me to forget everything? This will permanently delete all stored memories.")
            }
            let store = AssistantManager.shared.memoryStore
            do {
                try await store.clearAll()
                await AmoraMemoryService.shared.refresh()
                return .init(tool: .memory, status: .success, message: "I've cleared all your saved memories.")
            } catch {
                return .init(tool: .memory, status: .failure, message: "Failed to clear memories: \(error.localizedDescription)")
            }
        case .listShelfFiles:
            let shelf = FileShelfService.shared
            shelf.refreshItemStates()
            if shelf.items.isEmpty {
                return .init(tool: .fileShelf, status: .success, message: "Your File Shelf is empty. You can drag and drop files onto the shelf to pin them.", data: ["count": "0"])
            }
            let listStr = shelf.items.map { item in
                let status = item.isMissing ? "missing" : (item.fileSizeDescription ?? "available")
                return "• \(item.name) (\(status))"
            }.joined(separator: "\n")
            let count = shelf.items.count
            let countStr = count == 1 ? "1 item" : "\(count) items"
            return .init(tool: .fileShelf, status: .success, message: "Here are the \(countStr) on your File Shelf:\n\(listStr)", data: ["count": "\(count)"])
        case let .openShelfFile(name):
            let shelf = FileShelfService.shared
            guard let item = shelf.findItem(named: name) else {
                return .init(tool: .fileShelf, status: .failure, message: "I couldn't find '\(name)' on your File Shelf.")
            }
            guard !item.isMissing && FileManager.default.fileExists(atPath: item.url.path) else {
                shelf.markItemMissing(id: item.id)
                return .init(tool: .fileShelf, status: .failure, message: "Cannot open '\(item.name)': the file is missing or inaccessible.")
            }
            if shelf.openFile(item) {
                return .init(tool: .fileShelf, status: .success, message: "Opening \(item.name).", data: ["name": item.name, "path": item.url.path])
            } else {
                return .init(tool: .fileShelf, status: .failure, message: "Failed to open \(item.name).")
            }
        case let .revealShelfFile(name):
            let shelf = FileShelfService.shared
            guard let item = shelf.findItem(named: name) else {
                return .init(tool: .fileShelf, status: .failure, message: "I couldn't find '\(name)' on your File Shelf.")
            }
            guard !item.isMissing && FileManager.default.fileExists(atPath: item.url.path) else {
                shelf.markItemMissing(id: item.id)
                return .init(tool: .fileShelf, status: .failure, message: "Cannot reveal '\(item.name)': the file is missing or inaccessible.")
            }
            if shelf.revealFile(item) {
                return .init(tool: .fileShelf, status: .success, message: "Revealed \(item.name) in Finder.", data: ["name": item.name, "path": item.url.path])
            } else {
                return .init(tool: .fileShelf, status: .failure, message: "Failed to reveal \(item.name).")
            }
        case let .removeShelfFile(name):
            let shelf = FileShelfService.shared
            guard let item = shelf.findItem(named: name) else {
                return .init(tool: .fileShelf, status: .failure, message: "I couldn't find '\(name)' on your File Shelf.")
            }
            shelf.removeItem(id: item.id)
            return .init(tool: .fileShelf, status: .success, message: "Removed \(item.name) from your File Shelf. The original file was not deleted.", data: ["name": item.name])
        case let .clearShelfFiles(confirmed):
            guard confirmed else {
                return .init(tool: .fileShelf, status: .needsConfirmation, message: "Are you sure you want to clear your File Shelf? (This will not delete the original files from your Mac.)")
            }
            let count = FileShelfService.shared.items.count
            FileShelfService.shared.clearShelf()
            return .init(tool: .fileShelf, status: .success, message: "Cleared all \(count) items from your File Shelf. The original files were not deleted.", data: ["clearedCount": "\(count)"])
        }
    }
    private func mediaControl(playing: Bool) -> AMORAToolResult {
        MusicService.shared.checkCurrentTrack(); guard MusicService.shared.isAvailable else { return .init(tool: .music, status: .unsupported, message: "No supported media is available.") }; guard MusicService.shared.isPlaying != playing else { return .init(tool: .music, status: .success, message: playing ? "Media is already playing." : "Media is already paused.") }; if playing { MusicService.shared.play() } else { MusicService.shared.pause() }; return .init(tool: MusicService.shared.source == .youtube ? .browserMedia : .music, status: .success, message: playing ? "Media is playing." : "Media is paused.")
    }
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
        let key: String?
        let value: String?
        let query: String?
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
            case (.notes, "search"): return (call.text ?? call.name).map { .init(tool: tool, operation: .searchNotes(query: $0)) }
            case (.application, "open"): return call.name.map { .init(tool: tool, operation: .openApplication(name: $0)) }
            case (.folder, "open"): return call.name.map { .init(tool: tool, operation: .openFolder(name: $0)) }
            case (.system, "read"): return .init(tool: tool, operation: .readSystem)
            case (.view, "show"): return call.name.map { .init(tool: tool, operation: .showView(name: $0)) }
            case (.memory, "save"), (.memory, "remember"):
                let key = call.key ?? call.name ?? "preference"
                guard let value = call.value ?? call.text else { return nil }
                return .init(tool: tool, operation: .saveMemory(key: key, value: value))
            case (.memory, "search"), (.memory, "recall"):
                guard let query = call.query ?? call.text ?? call.name else { return nil }
                return .init(tool: tool, operation: .recallMemory(query: query))
            case (.memory, "list"):
                return .init(tool: tool, operation: .listMemories)
            case (.memory, "forget"), (.memory, "delete"):
                guard let query = call.query ?? call.text ?? call.name else { return nil }
                return .init(tool: tool, operation: .forgetMemory(query: query))
            case (.memory, "update"), (.memory, "change"), (.memory, "modify"):
                let key = call.key ?? call.name ?? call.query ?? "preference"
                guard let value = call.value ?? call.text else { return nil }
                return .init(tool: tool, operation: .updateMemory(key: key, value: value))
            case (.memory, "clear"):
                return .init(tool: tool, operation: .clearMemories(confirmed: true))
            case (.fileShelf, "list"), (.file, "list"):
                return .init(tool: tool, operation: .listShelfFiles)
            case (.fileShelf, "open"), (.file, "open"):
                return (call.name ?? call.text ?? call.query).map { .init(tool: tool, operation: .openShelfFile(name: $0)) }
            case (.fileShelf, "reveal"), (.file, "reveal"):
                return (call.name ?? call.text ?? call.query).map { .init(tool: tool, operation: .revealShelfFile(name: $0)) }
            case (.fileShelf, "remove"), (.file, "remove"), (.fileShelf, "unpin"), (.file, "unpin"):
                return (call.name ?? call.text ?? call.query).map { .init(tool: tool, operation: .removeShelfFile(name: $0)) }
            case (.fileShelf, "clear"), (.file, "clear"):
                return .init(tool: tool, operation: .clearShelfFiles(confirmed: true))
            default: return nil
            }
        }
        return requests.count == calls.count ? requests : nil
    }
}
