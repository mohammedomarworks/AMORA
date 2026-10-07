import Foundation

/// Strongly typed decision produced by the context-aware intelligence decision layer prior to action execution.
public enum AmoraActionDecision: Equatable, Sendable {
    /// Proceed with executing the action as planned.
    case execute(AmoraAction)

    /// The requested state already exists, so skip the redundant execution and report the current state.
    case alreadyInState(actionId: String, message: String, data: [String: String])

    public var shouldExecute: Bool {
        if case .execute = self { return true }
        return false
    }

    public var isAlreadyInState: Bool {
        if case .alreadyInState = self { return true }
        return false
    }
}

/// Represents the planned decision for a specific action in an action plan.
public struct AmoraActionPlanDecision: Equatable, Sendable {
    public let action: AmoraAction
    public let decision: AmoraActionDecision

    public init(action: AmoraAction, decision: AmoraActionDecision) {
        self.action = action
        self.decision = decision
    }
}

/// Decoupled protocol for the context-aware action decision layer.
public protocol AmoraActionDeciding: Sendable {
    /// Evaluates a single action against context to determine whether to execute or avoid redundant action.
    func decide(action: AmoraAction, context: AmoraActionContext) -> AmoraActionDecision

    /// Evaluates a sequence of actions against context, modeling state progression across steps.
    func plan(actions: [AmoraAction], context: AmoraActionContext) -> [AmoraActionPlanDecision]

    /// Simulates the effect of an action on a snapshot for multi-step planning and state tracking.
    func updatingSnapshot(_ snapshot: AmoraContextSnapshot, afterExecuting action: AmoraAction) -> AmoraContextSnapshot
}

/// Production implementation of the context-aware action decision layer.
public struct AmoraActionDecisionEngine: AmoraActionDeciding {
    public init() {}

    public func decide(action: AmoraAction, context: AmoraActionContext) -> AmoraActionDecision {
        // If context awareness is OFF or no snapshot is provided, execute without context assumptions.
        guard let snapshot = context.snapshot else {
            return .execute(action)
        }

        switch action {
        case .pauseMusic:
            if let media = snapshot.media {
                let state = media.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if state == "paused" {
                    return .alreadyInState(
                        actionId: action.identifier,
                        message: "Music is already paused.",
                        data: ["source": media.source, "state": media.state]
                    )
                }
            }
            return .execute(action)

        case .playMusic:
            if let media = snapshot.media, media.isPlaying {
                let isSpotify = media.source.caseInsensitiveCompare("Spotify") == .orderedSame
                let msg = isSpotify ? "Music is already playing on Spotify." : "Music is already playing."
                return .alreadyInState(
                    actionId: action.identifier,
                    message: msg,
                    data: ["source": media.source, "state": media.state]
                )
            }
            return .execute(action)

        case .openApplication(let name):
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // 1. If opening Spotify and Spotify is already the active playing media:
            if trimmedName.caseInsensitiveCompare("Spotify") == .orderedSame,
               let media = snapshot.media,
               media.source.caseInsensitiveCompare("Spotify") == .orderedSame,
               media.isPlaying {
                return .alreadyInState(
                    actionId: action.identifier,
                    message: "Music is already playing on Spotify.",
                    data: ["source": "Spotify", "state": "playing", "name": trimmedName]
                )
            }

            // 2. If the requested application is already the frontmost active application:
            if let current = snapshot.currentApplication?.name,
               current.caseInsensitiveCompare(trimmedName) == .orderedSame {
                return .alreadyInState(
                    actionId: action.identifier,
                    message: "\(current) is already open.",
                    data: ["name": trimmedName]
                )
            }
            return .execute(action)

        case .openWorkspace(let section):
            if let amora = snapshot.amora {
                let state = amora.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if state == "workspace" {
                    if section == nil || section?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                        return .alreadyInState(
                            actionId: action.identifier,
                            message: "Workspace is already open.",
                            data: ["state": amora.state]
                        )
                    }
                }
            }
            return .execute(action)

        case .startTimer(let duration):
            if let timer = snapshot.timer, timer.running {
                let requestedSeconds = Int(duration)
                let isEquivalent: Bool
                if let existingDuration = timer.duration, existingDuration == requestedSeconds {
                    isEquivalent = true
                } else if timer.duration == nil && abs(timer.remainingSeconds - requestedSeconds) <= 2 {
                    isEquivalent = true
                } else {
                    isEquivalent = false
                }

                if isEquivalent {
                    let formatted = AmoraActionEngine.formatDuration(seconds: requestedSeconds)
                    return .alreadyInState(
                        actionId: action.identifier,
                        message: "A \(formatted) timer is already running (\(timer.remainingSeconds)s remaining).",
                        data: [
                            "seconds": "\(requestedSeconds)",
                            "remainingSeconds": "\(timer.remainingSeconds)"
                        ]
                    )
                }
            }
            return .execute(action)

        case .resumeTimer:
            if let timer = snapshot.timer, timer.running, timer.isPaused == false {
                return .alreadyInState(
                    actionId: action.identifier,
                    message: "Timer is already running.",
                    data: ["remainingSeconds": "\(timer.remainingSeconds)"]
                )
            }
            return .execute(action)

        case .pauseTimer:
            if let timer = snapshot.timer, timer.running, timer.isPaused == true {
                return .alreadyInState(
                    actionId: action.identifier,
                    message: "Timer is already paused.",
                    data: ["remainingSeconds": "\(timer.remainingSeconds)"]
                )
            }
            return .execute(action)

        default:
            return .execute(action)
        }
    }

    public func plan(actions: [AmoraAction], context: AmoraActionContext) -> [AmoraActionPlanDecision] {
        guard let initialSnapshot = context.snapshot else {
            return actions.map { AmoraActionPlanDecision(action: $0, decision: .execute($0)) }
        }

        var currentSnapshot = initialSnapshot
        var planDecisions: [AmoraActionPlanDecision] = []

        for action in actions {
            var stepContext = context
            stepContext.snapshot = currentSnapshot
            let decision = decide(action: action, context: stepContext)
            planDecisions.append(AmoraActionPlanDecision(action: action, decision: decision))

            switch decision {
            case .execute(let act):
                currentSnapshot = updatingSnapshot(currentSnapshot, afterExecuting: act)
            case .alreadyInState:
                break
            }
        }

        return planDecisions
    }

    public func updatingSnapshot(_ snapshot: AmoraContextSnapshot, afterExecuting action: AmoraAction) -> AmoraContextSnapshot {
        switch action {
        case .pauseMusic:
            let currentMedia = snapshot.media ?? .inactive
            let newMedia = AmoraMediaContext(
                source: currentMedia.source,
                state: "paused",
                title: currentMedia.title,
                artist: currentMedia.artist
            )
            return snapshot.updating(media: newMedia)

        case .playMusic:
            let currentMedia = snapshot.media ?? .inactive
            let source = (currentMedia.source == "None" || currentMedia.source.isEmpty) ? "Music" : currentMedia.source
            let newMedia = AmoraMediaContext(
                source: source,
                state: "playing",
                title: currentMedia.title,
                artist: currentMedia.artist
            )
            return snapshot.updating(media: newMedia)

        case .openWorkspace:
            return snapshot.updating(amora: AmoraUIContext(state: "workspace"))

        case .startTimer(let duration):
            let seconds = Int(duration)
            let newTimer = AmoraTimerContext(
                running: true,
                remainingSeconds: seconds,
                duration: seconds,
                isPaused: false
            )
            return snapshot.updating(timer: newTimer)

        case .cancelTimer:
            return snapshot.updating(timer: .stopped)

        case .openApplication(let name):
            return snapshot.updating(currentApplication: AmoraApplicationContext(name: name))

        default:
            return snapshot
        }
    }
}
