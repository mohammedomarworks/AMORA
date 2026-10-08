import Foundation

/// Result of evaluating a command against ephemeral conversational context.
public enum AmoraFollowUpResolution: Equatable, Sendable {
    case resolvedAction(AmoraAction)
    case resolvedCommand(AMORACommand)
    case ambiguous(prompt: String, candidates: [String])
    case unhandled
}

/// Protocol-driven evaluator resolving contextual follow-up commands.
public protocol AmoraContextualFollowUpResolving: Sendable {
    func resolve(
        input: String,
        context: AmoraConversationContext?,
        snapshot: AmoraContextSnapshot?,
        contextAwarenessEnabled: Bool
    ) -> AmoraFollowUpResolution
}

/// Production implementation of contextual follow-up resolution.
/// Understands pronouns (it, that, this), omitted targets, modifications, and follow-ups.
/// Handles ambiguity and respects Context Awareness OFF.
public struct AmoraContextualFollowUpResolver: AmoraContextualFollowUpResolving {
    public static let shared = AmoraContextualFollowUpResolver()

    public init() {}

    public func resolve(
        input: String,
        context: AmoraConversationContext?,
        snapshot: AmoraContextSnapshot?,
        contextAwarenessEnabled: Bool
    ) -> AmoraFollowUpResolution {
        // Requirement 7: Respect Context Awareness OFF
        guard contextAwarenessEnabled else {
            return .unhandled
        }

        // Ephemeral context must exist and not be expired
        guard let ctx = context, !ctx.isExpired(at: Date()), !ctx.isEmpty else {
            return .unhandled
        }

        let rawTrimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = AMORACommandParser.normalize(rawTrimmed)
        guard !normalized.isEmpty else { return .unhandled }

        // --- 1. Timer Modification (Relative addition: "add 5 minutes to it", "extend it by 10 mins") ---
        if let relSeconds = parseRelativeTimerModification(normalized) {
            let isTimerEligible = ctx.activeTimerReference != nil ||
                (snapshot?.timer?.running == true) ||
                isActionTimer(ctx.lastRelevantAction)
            if isTimerEligible {
                return .resolvedCommand(.addTimerTime(duration: relSeconds))
            } else {
                return .ambiguous(prompt: "There isn't an active timer to extend.", candidates: [])
            }
        }

        // --- 2. Timer Modification (Absolute change: "make it 15 minutes", "change it to 20 minutes") ---
        if let absSeconds = parseAbsoluteTimerModification(normalized) {
            let isTimerEligible = ctx.activeTimerReference != nil ||
                (snapshot?.timer?.running == true) ||
                isActionTimer(ctx.lastRelevantAction)
            if isTimerEligible {
                return .resolvedAction(.startTimer(duration: absSeconds))
            } else {
                return .ambiguous(prompt: "There isn't an active timer to change.", candidates: [])
            }
        }

        // --- 3. Workspace Section Follow-up ("switch to notes", "change that to clipboard", "notes") ---
        if let workspaceResolution = resolveWorkspaceFollowUp(normalized, ctx: ctx, snapshot: snapshot) {
            return workspaceResolution
        }

        // --- 4. Application Follow-up ("open it", "open that", "open it again", "launch it") ---
        if isAppFollowUp(normalized) {
            if let app = ctx.lastReferencedApp, !app.isEmpty {
                return .resolvedAction(.openApplication(name: app))
            } else {
                return .ambiguous(prompt: "Which application would you like me to open?", candidates: [])
            }
        }

        // --- 5. Media Skip / Previous Follow-up ("next", "skip it", "previous", "previous on that") ---
        if isMediaSkipFollowUp(normalized) {
            return .resolvedAction(.nextTrack)
        }
        if isMediaPreviousFollowUp(normalized) {
            return .resolvedAction(.previousTrack)
        }

        // --- 6. Ambiguity Check: Pause / Stop / Resume / Cancel ---
        let isPause = isPauseFollowUp(normalized)
        let isStop = isStopFollowUp(normalized)
        let isResume = isResumeFollowUp(normalized)
        let isPlay = isPlayFollowUp(normalized)
        let isCancel = isCancelFollowUp(normalized)

        if isPause || isStop || isResume || isPlay || isCancel {
            let timerActive = (ctx.activeTimerReference != nil) || (snapshot?.timer?.running == true)
            let mediaActive = (ctx.lastReferencedMedia?.isPlaying == true) || (snapshot?.media?.isPlaying == true)

            // Ambiguity check: When both are active and the last action does not unambiguously distinguish
            if timerActive && mediaActive && (isPause || isStop || isResume) {
                let lastWasMedia = isActionMedia(ctx.lastRelevantAction)
                let lastWasTimer = isActionTimer(ctx.lastRelevantAction)

                if !lastWasMedia && !lastWasTimer {
                    return .ambiguous(prompt: "Did you mean the timer or music?", candidates: ["Timer", "Music"])
                }
            }

            // Route to Timer
            if timerActive && !mediaActive {
                if isPause { return .resolvedAction(.pauseTimer) }
                if isResume { return .resolvedAction(.resumeTimer) }
                if isStop || isCancel { return .resolvedAction(.cancelTimer) }
            }

            // Route to Media
            if mediaActive && !timerActive {
                if isPause || isStop { return .resolvedAction(.pauseMusic) }
                if isResume || isPlay { return .resolvedAction(.playMusic) }
            }

            // If last action specifically broke the tie:
            if isActionMedia(ctx.lastRelevantAction) {
                if isPause || isStop { return .resolvedAction(.pauseMusic) }
                if isResume || isPlay { return .resolvedAction(.playMusic) }
            } else if isActionTimer(ctx.lastRelevantAction) {
                if isPause { return .resolvedAction(.pauseTimer) }
                if isResume { return .resolvedAction(.resumeTimer) }
                if isStop || isCancel { return .resolvedAction(.cancelTimer) }
            }

            // Fallback for cancel commands directed at timer:
            if isCancel && timerActive {
                return .resolvedAction(.cancelTimer)
            }
        }

        return .unhandled
    }

    // MARK: - Private Helpers

    private func isActionTimer(_ action: AmoraAction?) -> Bool {
        guard let action else { return false }
        switch action {
        case .startTimer, .cancelTimer, .pauseTimer, .resumeTimer:
            return true
        default:
            return false
        }
    }

    private func isActionMedia(_ action: AmoraAction?) -> Bool {
        guard let action else { return false }
        switch action {
        case .playMusic, .pauseMusic, .nextTrack, .previousTrack:
            return true
        default:
            return false
        }
    }

    private func isAppFollowUp(_ normalized: String) -> Bool {
        let appPatterns = [
            "open it", "open that", "open this",
            "open it again", "open that again", "open this again",
            "launch it", "launch that", "launch this",
            "reopen it", "reopen that", "reopen this",
            "open app", "launch app"
        ]
        return appPatterns.contains(normalized)
    }

    private func isMediaSkipFollowUp(_ normalized: String) -> Bool {
        let skipPatterns = [
            "skip", "skip it", "skip that", "skip this",
            "next", "next track", "next song",
            "next on it", "next on that", "skip track", "skip song"
        ]
        return skipPatterns.contains(normalized)
    }

    private func isMediaPreviousFollowUp(_ normalized: String) -> Bool {
        let prevPatterns = [
            "previous", "previous track", "previous song",
            "previous on it", "previous on that",
            "replay it", "restart song", "restart track"
        ]
        return prevPatterns.contains(normalized)
    }

    private func isPauseFollowUp(_ normalized: String) -> Bool {
        let pausePatterns = ["pause", "pause it", "pause that", "pause this"]
        return pausePatterns.contains(normalized)
    }

    private func isStopFollowUp(_ normalized: String) -> Bool {
        let stopPatterns = ["stop", "stop it", "stop that", "stop this"]
        return stopPatterns.contains(normalized)
    }

    private func isResumeFollowUp(_ normalized: String) -> Bool {
        let resumePatterns = ["resume", "resume it", "resume that", "resume this"]
        return resumePatterns.contains(normalized)
    }

    private func isPlayFollowUp(_ normalized: String) -> Bool {
        let playPatterns = ["play", "play it", "play that", "play this"]
        return playPatterns.contains(normalized)
    }

    private func isCancelFollowUp(_ normalized: String) -> Bool {
        let cancelPatterns = [
            "cancel", "cancel it", "cancel that", "cancel this",
            "turn it off", "turn that off", "clear it", "clear that"
        ]
        return cancelPatterns.contains(normalized)
    }

    // MARK: - Timer Parsing

    private func parseRelativeTimerModification(_ text: String) -> TimeInterval? {
        let isRelative = text.hasPrefix("add ") ||
            text.hasPrefix("extend ") ||
            text.contains("more minutes") ||
            text.contains("more seconds")

        guard isRelative else { return nil }
        return extractDurationSeconds(from: text)
    }

    private func parseAbsoluteTimerModification(_ text: String) -> TimeInterval? {
        let absoluteStarters = [
            "make it ", "make that ", "make this ",
            "change it to ", "change that to ", "change this to ",
            "set it to ", "set that to ", "set this to ",
            "change timer to ", "set timer to ", "make timer ", "update timer to "
        ]
        guard absoluteStarters.contains(where: { text.hasPrefix($0) }) else { return nil }
        return extractDurationSeconds(from: text)
    }

    private func extractDurationSeconds(from text: String) -> TimeInterval? {
        let pattern = #"\b(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#
        guard let match = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matchStr = String(text[match])
        let parts = matchStr.split(separator: " ")
        guard let numPart = parts.first, let val = Double(numPart), val > 0 else { return nil }
        let unitPart = parts.count > 1 ? String(parts[1]) : String(matchStr.dropFirst(numPart.count)).trimmingCharacters(in: .whitespaces)

        let seconds: Double
        if unitPart.hasPrefix("hour") || unitPart.hasPrefix("hr") || unitPart == "h" {
            seconds = val * 3600
        } else if unitPart.hasPrefix("sec") || unitPart == "s" {
            seconds = val
        } else {
            seconds = val * 60
        }
        guard seconds >= 1, seconds <= 86400 else { return nil }
        return seconds
    }

    // MARK: - Workspace Parsing

    private func resolveWorkspaceFollowUp(
        _ normalized: String,
        ctx: AmoraConversationContext,
        snapshot: AmoraContextSnapshot?
    ) -> AmoraFollowUpResolution? {
        let isWorkspaceContext = ctx.currentWorkspaceSection != nil ||
            ctx.lastRelevantAction == .openWorkspace() ||
            (snapshot?.amora?.state.lowercased() == "workspace")

        // 1. Pronoun referring to workspace: "open that", "open it", "show that", "show it"
        if (normalized == "open it" || normalized == "open that" || normalized == "show it" || normalized == "show that") &&
            isWorkspaceContext &&
            ctx.lastReferencedApp == nil {
            return .resolvedAction(.openWorkspace(section: nil))
        }

        // 2. Section switching
        let sectionMap: [(keywords: [String], sectionName: String)] = [
            (["notes", "note"], "Notes"),
            (["clipboard", "clip board"], "Clipboard"),
            (["file shelf", "files", "file", "pinned files"], "File Shelf"),
            (["overview", "system", "stats"], "Overview")
        ]

        let switchPrefixes = [
            "switch to ", "go to ", "show ", "open ",
            "switch it to ", "switch that to ", "switch this to ",
            "change to ", "change it to ", "change that to ",
            "switch section to ", "change section to "
        ]

        for prefix in switchPrefixes {
            if normalized.hasPrefix(prefix) {
                let target = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                for (keywords, section) in sectionMap {
                    if keywords.contains(target) {
                        return .resolvedAction(.openWorkspace(section: section))
                    }
                }
            }
        }

        // If in explicit workspace context, bare section names switch sections:
        if isWorkspaceContext {
            for (keywords, section) in sectionMap {
                if keywords.contains(normalized) {
                    return .resolvedAction(.openWorkspace(section: section))
                }
            }
        }

        return nil
    }
}
