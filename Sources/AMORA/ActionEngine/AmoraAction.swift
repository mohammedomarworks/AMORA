import Foundation

/// Strongly typed, controlled actions executable by the AMORA Action Engine.
/// Arbitrary shell commands, scripts, and unvalidated process executions are strictly forbidden.
public enum AmoraAction: Equatable, Sendable {
    case playMusic
    case pauseMusic
    case nextTrack
    case previousTrack
    case openApplication(name: String)
    case openFolder(location: String)
    case openWorkspace(section: String? = nil)
    case startTimer(duration: TimeInterval)
    case cancelTimer
    case pauseTimer
    case resumeTimer
    case showNotification(message: String)
    case confirmTest(actionName: String, prompt: String)
    case saveMemory(key: String, value: String)
    case forgetMemory(query: String)
    case updateMemory(target: String, newValue: String)
    case clearMemories(confirmed: Bool)
    case listShelfFiles
    case openShelfFile(name: String)
    case revealShelfFile(name: String)
    case removeShelfFile(name: String)
    case clearShelf(confirmed: Bool)

    public var identifier: String {
        switch self {
        case .playMusic: return "media.play"
        case .pauseMusic: return "media.pause"
        case .nextTrack: return "media.next"
        case .previousTrack: return "media.previous"
        case .openApplication: return "app.open"
        case .openFolder: return "folder.open"
        case .openWorkspace: return "workspace.open"
        case .startTimer: return "timer.start"
        case .cancelTimer: return "timer.cancel"
        case .pauseTimer: return "timer.pause"
        case .resumeTimer: return "timer.resume"
        case .showNotification: return "amora.notification"
        case .confirmTest: return "system.confirm_test"
        case .saveMemory: return "memory.save"
        case .forgetMemory: return "memory.forget"
        case .updateMemory: return "memory.update"
        case .clearMemories: return "memory.clear"
        case .listShelfFiles: return "fileshelf.list"
        case .openShelfFile: return "fileshelf.open"
        case .revealShelfFile: return "fileshelf.reveal"
        case .removeShelfFile: return "fileshelf.remove"
        case .clearShelf: return "fileshelf.clear"
        }
    }

    public var humanReadableName: String {
        switch self {
        case .playMusic: return "Play Music"
        case .pauseMusic: return "Pause Music"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .openApplication(let name): return "Open \(name)"
        case .openFolder(let location): return "Open \(location.capitalized)"
        case .openWorkspace(let section):
            if let section, !section.isEmpty {
                return "Open Workspace (\(section))"
            }
            return "Open Workspace"
        case .startTimer(let duration):
            return "Start Timer (\(Int(duration))s)"
        case .cancelTimer: return "Cancel Timer"
        case .pauseTimer: return "Pause Timer"
        case .resumeTimer: return "Resume Timer"
        case .showNotification(let msg): return "Show Notification: \(msg)"
        case .confirmTest(let name, _): return "Confirm: \(name)"
        case .saveMemory(let key, _): return "Save Memory: \(key)"
        case .forgetMemory(let query): return "Forget Memory: \(query)"
        case .updateMemory(let target, let value): return "Update Memory (\(target): \(value))"
        case .clearMemories: return "Clear Memories"
        case .listShelfFiles: return "List File Shelf"
        case .openShelfFile(let name): return "Open File: \(name)"
        case .revealShelfFile(let name): return "Reveal File: \(name)"
        case .removeShelfFile(let name): return "Remove from Shelf: \(name)"
        case .clearShelf: return "Clear File Shelf"
        }
    }

    public static func == (lhs: AmoraAction, rhs: AmoraAction) -> Bool {
        switch (lhs, rhs) {
        case (.playMusic, .playMusic),
             (.pauseMusic, .pauseMusic),
             (.nextTrack, .nextTrack),
             (.previousTrack, .previousTrack),
             (.cancelTimer, .cancelTimer),
             (.pauseTimer, .pauseTimer),
             (.resumeTimer, .resumeTimer),
             (.listShelfFiles, .listShelfFiles):
            return true
        case (.openApplication(let lName), .openApplication(let rName)):
            return lName.caseInsensitiveCompare(rName) == .orderedSame
        case (.openFolder(let lLoc), .openFolder(let rLoc)):
            return lLoc.caseInsensitiveCompare(rLoc) == .orderedSame
        case (.openWorkspace(let lSec), .openWorkspace(let rSec)):
            if lSec == nil && rSec == nil { return true }
            guard let lSec, let rSec else { return false }
            return lSec.caseInsensitiveCompare(rSec) == .orderedSame
        case (.startTimer(let lDur), .startTimer(let rDur)):
            return abs(lDur - rDur) < 0.001
        case (.showNotification(let lMsg), .showNotification(let rMsg)):
            return lMsg == rMsg
        case (.confirmTest(let lName, let lPrompt), .confirmTest(let rName, let rPrompt)):
            return lName == rName && lPrompt == rPrompt
        case (.saveMemory(let lK, let lV), .saveMemory(let rK, let rV)):
            return lK.caseInsensitiveCompare(rK) == .orderedSame && lV == rV
        case (.updateMemory(let lT, let lV), .updateMemory(let rT, let rV)):
            return lT.caseInsensitiveCompare(rT) == .orderedSame && lV == rV
        case (.forgetMemory(let lQ), .forgetMemory(let rQ)):
            return lQ.caseInsensitiveCompare(rQ) == .orderedSame
        case (.clearMemories(let lC), .clearMemories(let rC)):
            return lC == rC
        case (.openShelfFile(let lName), .openShelfFile(let rName)):
            return lName.caseInsensitiveCompare(rName) == .orderedSame
        case (.revealShelfFile(let lName), .revealShelfFile(let rName)):
            return lName.caseInsensitiveCompare(rName) == .orderedSame
        case (.removeShelfFile(let lName), .removeShelfFile(let rName)):
            return lName.caseInsensitiveCompare(rName) == .orderedSame
        case (.clearShelf(let lC), .clearShelf(let rC)):
            return lC == rC
        default:
            return false
        }
    }
}

/// Errors occurring while resolving an unstructured request or call into an `AmoraAction`.
public enum AmoraActionResolutionError: Error, Equatable, Sendable {
    case missingParameter(String)
    case invalidParameter(String)
    case unknownAction(String)

    public var message: String {
        switch self {
        case .missingParameter(let msg),
             .invalidParameter(let msg),
             .unknownAction(let msg):
            return msg
        }
    }
}

/// Structured request representation received from AI models or external callers.
public struct AmoraActionRequest: Codable, Equatable, Sendable {
    public let actionId: String
    public let parameters: [String: String]

    public init(actionId: String, parameters: [String: String] = [:]) {
        self.actionId = actionId
        self.parameters = parameters
    }

    /// Resolves this request into a strongly typed `AmoraAction` if known and well-formed.
    public func resolveAction() -> Result<AmoraAction, AmoraActionResolutionError> {
        let normalizedId = actionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedId {
        case "media.play", "play_music", "playmusic":
            return .success(.playMusic)
        case "media.pause", "pause_music", "pausemusic":
            return .success(.pauseMusic)
        case "media.next", "next_track", "nexttrack":
            return .success(.nextTrack)
        case "media.previous", "previous_track", "previoustrack":
            return .success(.previousTrack)
        case "app.open", "open_application", "openapplication":
            guard let name = parameters["name"] ?? parameters["app"] ?? parameters["application"],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'name' parameter for openApplication action."))
            }
            return .success(.openApplication(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "folder.open", "open_folder", "openfolder", "location.open", "open_location", "openlocation":
            guard let loc = parameters["location"] ?? parameters["folder"] ?? parameters["name"] ?? parameters["path"],
                  !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'location' parameter for folder.open action."))
            }
            return .success(.openFolder(location: loc.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "workspace.open", "open_workspace", "openworkspace":
            let section = parameters["section"]
            return .success(.openWorkspace(section: section))
        case "timer.start", "start_timer", "starttimer":
            if let durationStr = parameters["duration"] ?? parameters["seconds"] ?? parameters["time"] {
                if let seconds = Double(durationStr), seconds > 0 {
                    return .success(.startTimer(duration: seconds))
                }
                return .failure(.invalidParameter("Missing or invalid 'duration' parameter for startTimer action."))
            }
            // Default to 25 minutes (1500 seconds) when duration is omitted by the user
            return .success(.startTimer(duration: 1500))
        case "timer.cancel", "cancel_timer", "canceltimer", "timer.stop", "stop_timer", "stoptimer",
             "timer.end", "end_timer", "endtimer", "timer.turnoff", "turn_off_timer", "turnofftimer",
             "timer.clear", "clear_timer", "cleartimer":
            return .success(.cancelTimer)
        case "timer.pause", "pause_timer", "pausetimer":
            return .success(.pauseTimer)
        case "timer.resume", "resume_timer", "resumetimer":
            return .success(.resumeTimer)
        case "amora.notification", "notification.show", "shownotification", "notification":
            guard let msg = parameters["message"] ?? parameters["text"] ?? parameters["prompt"] ?? parameters["title"],
                  !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'message' parameter for showNotification action."))
            }
            return .success(.showNotification(message: msg.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "system.confirm_test", "confirm_test", "test.confirm":
            let name = parameters["name"] ?? "Test Action"
            let prompt = parameters["prompt"] ?? "Are you sure you want to run this test action?"
            return .success(.confirmTest(actionName: name, prompt: prompt))
        case "memory.save", "save_memory", "savememory", "remember_fact", "rememberfact", "remember":
            guard let key = parameters["key"] ?? parameters["name"] ?? parameters["title"] ?? parameters["topic"],
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'key' parameter for memory.save action."))
            }
            guard let value = parameters["value"] ?? parameters["content"] ?? parameters["fact"] ?? parameters["text"] ?? parameters["details"],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'value' parameter for memory.save action."))
            }
            return .success(.saveMemory(
                key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                value: value.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        case "memory.forget", "forget_memory", "forgetmemory", "delete_memory", "deletememory", "forget":
            guard let query = parameters["query"] ?? parameters["key"] ?? parameters["target"] ?? parameters["name"] ?? parameters["topic"],
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'query' parameter for memory.forget action."))
            }
            return .success(.forgetMemory(query: query.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "memory.update", "update_memory", "updatememory", "change_memory", "changememory", "update":
            guard let target = parameters["key"] ?? parameters["target"] ?? parameters["name"] ?? parameters["topic"] ?? parameters["query"],
                  !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'key' or 'target' parameter for memory.update action."))
            }
            guard let value = parameters["value"] ?? parameters["newValue"] ?? parameters["content"] ?? parameters["text"],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'value' parameter for memory.update action."))
            }
            return .success(.updateMemory(
                target: target.trimmingCharacters(in: .whitespacesAndNewlines),
                newValue: value.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        case "memory.clear", "clear_memories", "clearmemories", "clear_memory", "clearmemory":
            let confirmed = parameters["confirmed"] == "true"
            return .success(.clearMemories(confirmed: confirmed))
        case "fileshelf.list", "list_shelf_files", "list_files", "shelf.list", "files.list":
            return .success(.listShelfFiles)
        case "fileshelf.open", "open_shelf_file", "open_file", "file.open":
            guard let name = parameters["name"] ?? parameters["file"] ?? parameters["filename"] ?? parameters["target"],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'name' parameter for openShelfFile action."))
            }
            return .success(.openShelfFile(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "fileshelf.reveal", "reveal_shelf_file", "reveal_file", "file.reveal":
            guard let name = parameters["name"] ?? parameters["file"] ?? parameters["filename"] ?? parameters["target"],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'name' parameter for revealShelfFile action."))
            }
            return .success(.revealShelfFile(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "fileshelf.remove", "remove_shelf_file", "remove_file", "file.remove", "unpin_file":
            guard let name = parameters["name"] ?? parameters["file"] ?? parameters["filename"] ?? parameters["target"],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingParameter("Missing required 'name' parameter for removeShelfFile action."))
            }
            return .success(.removeShelfFile(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "fileshelf.clear", "clear_shelf", "clear_fileshelf", "shelf.clear":
            let confirmed = parameters["confirmed"] == "true"
            return .success(.clearShelf(confirmed: confirmed))
        default:
            return .failure(.unknownAction("Unknown action identifier: '\(actionId)'."))
        }
    }
}

/// Structured action plan produced by AI intent resolution.
public struct AmoraActionPlan: Codable, Sendable {
    public struct ActionCall: Codable, Sendable {
        public let action: String
        public let duration: Double?
        public let seconds: Int?
        public let name: String?
        public let location: String?
        public let section: String?
        public let key: String?
        public let value: String?
        public let query: String?
        public let parameters: [String: String]?

        public init(
            action: String,
            duration: Double? = nil,
            seconds: Int? = nil,
            name: String? = nil,
            location: String? = nil,
            section: String? = nil,
            key: String? = nil,
            value: String? = nil,
            query: String? = nil,
            parameters: [String: String]? = nil
        ) {
            self.action = action
            self.duration = duration
            self.seconds = seconds
            self.name = name
            self.location = location
            self.section = section
            self.key = key
            self.value = value
            self.query = query
            self.parameters = parameters
        }

        public func toActionRequest() -> AmoraActionRequest {
            var params = parameters ?? [:]
            if let duration { params["duration"] = "\(duration)" }
            if let seconds { params["seconds"] = "\(seconds)" }
            if let name { params["name"] = name }
            if let location { params["location"] = location }
            if let section { params["section"] = section }
            if let key { params["key"] = key }
            if let value { params["value"] = value }
            if let query { params["query"] = query }
            return AmoraActionRequest(actionId: action, parameters: params)
        }
    }

    public let actions: [ActionCall]

    public init(actions: [ActionCall]) {
        self.actions = actions
    }

    public func resolveActions() -> [Result<AmoraAction, AmoraActionResolutionError>] {
        actions.map { $0.toActionRequest().resolveAction() }
    }
}
