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
             (.resumeTimer, .resumeTimer):
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
            if let durationStr = parameters["duration"] ?? parameters["seconds"] ?? parameters["time"],
               let seconds = Double(durationStr), seconds > 0 {
                return .success(.startTimer(duration: seconds))
            }
            return .failure(.invalidParameter("Missing or invalid 'duration' parameter for startTimer action."))
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
        public let parameters: [String: String]?

        public init(
            action: String,
            duration: Double? = nil,
            seconds: Int? = nil,
            name: String? = nil,
            location: String? = nil,
            section: String? = nil,
            parameters: [String: String]? = nil
        ) {
            self.action = action
            self.duration = duration
            self.seconds = seconds
            self.name = name
            self.location = location
            self.section = section
            self.parameters = parameters
        }

        public func toActionRequest() -> AmoraActionRequest {
            var params = parameters ?? [:]
            if let duration { params["duration"] = "\(duration)" }
            if let seconds { params["seconds"] = "\(seconds)" }
            if let name { params["name"] = name }
            if let location { params["location"] = location }
            if let section { params["section"] = section }
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
