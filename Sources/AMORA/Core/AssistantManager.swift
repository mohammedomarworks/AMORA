import Foundation
import Observation

enum AssistantState: Equatable, Sendable { case idle, thinking, responding, failed, cancelled }

@Observable @MainActor
final class AssistantManager {
    static let shared = AssistantManager(provider: UnavailableAIProvider(kind: .local), providerIsInjected: false)

    private var provider: any AIProvider
    private let providerIsInjected: Bool
    var providerAvailability: AIAvailability { provider.availability }
    var isProviderAvailable: Bool { provider.isAvailable }
    private(set) var state: AssistantState = .idle
    private(set) var response: String?
    private(set) var lastError: AIProviderError?
    private(set) var conversation = AIConversation()
    private var requestTask: Task<String, Never>?

    init(provider: any AIProvider, providerIsInjected: Bool = true) {
        self.provider = provider
        self.providerIsInjected = providerIsInjected
    }

    func configure(provider: any AIProvider) { self.provider = provider }

    func submit(_ input: String, settings: AISettingsSnapshot) async -> String {
        cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return "I don't know how to help with that yet." }
            return await self.performSubmit(input, settings: settings)
        }
        requestTask = task
        let result = await task.value
        if requestTask != nil { requestTask = nil }
        return result
    }

    private func performSubmit(_ input: String, settings: AISettingsSnapshot) async -> String {
        if !providerIsInjected { configure(provider: AIProviderFactory.make(for: settings)) }
        guard settings.enabled else {
            state = .failed
            lastError = .unavailable
            let fallback = "AI Assistant is turned off in Settings."
            response = fallback
            AMORAContext.shared.setAIResponse(fallback)
            AMORAEventCenter.shared.emit(.aiFailed)
            return fallback
        }

        guard provider.isAvailable else {
            state = .failed
            lastError = unavailableError(for: provider)
            let fallback = message(for: lastError!)
            response = fallback
            AMORAContext.shared.setAIResponse(fallback)
            AMORAEventCenter.shared.emit(.aiFailed)
            return fallback
        }

        state = .thinking
        response = nil
        lastError = nil
        AMORAContext.shared.setAIResponse(nil)
        AMORAEventCenter.shared.emit(.aiThinking)
        AmoraActionExecutionCoordinator.shared.beginThinking()

        var messages = conversation.messages
        messages.append(AIMessage(role: .user, content: """
[AMORA action policy]
You must execute actions by returning strict JSON {"actions":[{"action":"...","name":"...","location":"...","duration":10}]}.
Approved actions:
- media.play, media.pause, media.next, media.previous
- app.open (with name)
- folder.open (with location: 'downloads', 'documents', 'desktop', or 'home')
- workspace.open (with optional section)
- timer.start (with duration in seconds)
- timer.cancel (no duration)
- timer.pause
- timer.resume

For multi-action requests, include each action in sequence within the "actions" array:
- "Open Spotify and start a 25 minute timer" -> {"actions":[{"action":"app.open","name":"Spotify"},{"action":"timer.start","duration":1500}]}
- "Open Finder and then open Downloads" -> {"actions":[{"action":"app.open","name":"Finder"},{"action":"folder.open","location":"downloads"}]}
- "Play music and open Workspace" -> {"actions":[{"action":"media.play"},{"action":"workspace.open"}]}
- "Start a 10 second timer and open VS Code" -> {"actions":[{"action":"timer.start","duration":10},{"action":"app.open","name":"VS Code"}]}
- "Open VS Code, start Spotify, start a 45 minute timer and open Workspace" -> {"actions":[{"action":"app.open","name":"VS Code"},{"action":"media.play"},{"action":"timer.start","duration":2700},{"action":"workspace.open"}]}

If the user asks to cancel, stop, end, or turn off a timer, output {"actions":[{"action":"timer.cancel"}]}. Do not ask for duration on cancellation.
Never request shell commands, arbitrary paths, unknown tools, or destructive actions.
If no action is needed, answer normally.
"""))
        if settings.contextAwarenessEnabled {
            let convCtx = AmoraConversationContextManager.shared.validContext()
            if let context = AIContextComposer.relevantContext(for: input, conversationContext: convCtx) {
                messages.append(AIMessage(role: .user, content: "[System context]\n\(context)"))
            }
        }
        let userMessage = AIMessage(role: .user, content: input)
        messages.append(userMessage)
        conversation.append(userMessage)

        let normalizedInput = AMORACommandParser.normalize(input)
        let isTimerCancellationInput = normalizedInput.contains("timer") &&
            (normalizedInput.contains("cancel") || normalizedInput.contains("stop") || normalizedInput.contains("end") || normalizedInput.contains("turn off") || normalizedInput.contains("clear"))
        let isTimerPauseInput = normalizedInput.contains("timer") && normalizedInput.contains("pause")
        let isTimerResumeInput = normalizedInput.contains("timer") && normalizedInput.contains("resume")

        do {
            let rawAnswer = try await provider.send(messages: messages, model: settings.model, apiKey: settings.apiKey)
            try Task.checkCancellation()
            let answer: String
            let extractedJSONData = Self.extractJSONData(from: rawAnswer)
            if let data = extractedJSONData,
               var actionPlan = try? JSONDecoder().decode(AmoraActionPlan.self, from: data),
               !actionPlan.actions.isEmpty {
                // Prevent stale conversation history containing durations from overriding a cancellation intent
                if isTimerCancellationInput {
                    let sanitizedActions = actionPlan.actions.map { call in
                        if call.action == "timer.start" {
                            return AmoraActionPlan.ActionCall(action: "timer.cancel")
                        }
                        return call
                    }
                    actionPlan = AmoraActionPlan(actions: sanitizedActions)
                }
                let convContext = settings.contextAwarenessEnabled ? AmoraConversationContextManager.shared.validContext() : nil
                let actionContext = AmoraActionContext(
                    snapshot: settings.contextAwarenessEnabled ? AmoraContextProvider.shared.currentSnapshot : nil,
                    conversationContext: convContext
                )
                let results = await AmoraActionEngine.shared.executePlan(actionPlan, context: actionContext)
                AmoraContextProvider.shared.captureSnapshot()
                if settings.contextAwarenessEnabled {
                    for callResult in actionPlan.resolveActions() {
                        if case .success(let act) = callResult {
                            AmoraConversationContextManager.shared.recordAction(act, date: Date())
                        }
                    }
                }
                answer = AmoraActionResult.combineMessages(from: results)
            } else if isTimerCancellationInput {
                let convContext = settings.contextAwarenessEnabled ? AmoraConversationContextManager.shared.validContext() : nil
                let actionContext = AmoraActionContext(
                    snapshot: settings.contextAwarenessEnabled ? AmoraContextProvider.shared.currentSnapshot : nil,
                    conversationContext: convContext
                )
                let results = await AmoraActionEngine.shared.executeSequence([.cancelTimer], context: actionContext)
                if settings.contextAwarenessEnabled {
                    AmoraConversationContextManager.shared.recordAction(.cancelTimer, date: Date())
                }
                answer = AmoraActionResult.combineMessages(from: results)
            } else if isTimerPauseInput {
                let convContext = settings.contextAwarenessEnabled ? AmoraConversationContextManager.shared.validContext() : nil
                let actionContext = AmoraActionContext(
                    snapshot: settings.contextAwarenessEnabled ? AmoraContextProvider.shared.currentSnapshot : nil,
                    conversationContext: convContext
                )
                let results = await AmoraActionEngine.shared.executeSequence([.pauseTimer], context: actionContext)
                if settings.contextAwarenessEnabled {
                    AmoraConversationContextManager.shared.recordAction(.pauseTimer, date: Date())
                }
                answer = AmoraActionResult.combineMessages(from: results)
            } else if isTimerResumeInput {
                let convContext = settings.contextAwarenessEnabled ? AmoraConversationContextManager.shared.validContext() : nil
                let actionContext = AmoraActionContext(
                    snapshot: settings.contextAwarenessEnabled ? AmoraContextProvider.shared.currentSnapshot : nil,
                    conversationContext: convContext
                )
                let results = await AmoraActionEngine.shared.executeSequence([.resumeTimer], context: actionContext)
                if settings.contextAwarenessEnabled {
                    AmoraConversationContextManager.shared.recordAction(.resumeTimer, date: Date())
                }
                answer = AmoraActionResult.combineMessages(from: results)
            } else if let data = extractedJSONData,
                      let plan = try? JSONDecoder().decode(AMORAToolPlan.self, from: data),
                      let requests = plan.requests() {
                let results = requests.map { AMORAToolRegistry.shared.execute($0) }
                if let confirmation = results.first(where: { $0.status == .needsConfirmation }) {
                    answer = "I need your confirmation before I do that. \(confirmation.message)"
                } else {
                    answer = results.map(\.message).joined(separator: " ")
                }
                AmoraActionExecutionCoordinator.shared.reset()
            } else {
                answer = rawAnswer
                AmoraActionExecutionCoordinator.shared.reset()
            }
            let assistantMessage = AIMessage(role: .assistant, content: answer)
            conversation.append(assistantMessage)
            state = .responding
            response = answer
            AMORAContext.shared.setAIResponse(answer)
            AMORAEventCenter.shared.emit(.aiSucceeded)
            return answer
        } catch is CancellationError {
            state = .cancelled
            lastError = .cancelled
            AMORAEventCenter.shared.emit(.aiCancelled)
            return "Okay — stopped."
        } catch let error as AIProviderError {
            state = .failed
            lastError = error
            AMORAEventCenter.shared.emit(.aiFailed)
            let message = self.message(for: error)
            response = message
            AMORAContext.shared.setAIResponse(message)
            return message
        } catch {
            state = .failed
            lastError = .networkFailure
            AMORAEventCenter.shared.emit(.aiFailed)
            response = "I can't reach that AI service right now."
            AMORAContext.shared.setAIResponse(response)
            return response!
        }
    }

    private static func cleanJSONString(_ str: String) -> String {
        var cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        // Fix missing opening quote on keys after comma, e.g. ,key": -> ,"key":
        cleaned = cleaned.replacingOccurrences(of: #",([a-zA-Z0-9_]+)":"#, with: #",\"$1\":"#, options: .regularExpression)
        // Fix missing opening quote on keys after brace, e.g. {key": -> {"key":
        cleaned = cleaned.replacingOccurrences(of: #"\{([a-zA-Z0-9_]+)":"#, with: #"{\"$1\":"#, options: .regularExpression)
        return cleaned
    }

    private static func extractJSONData(from text: String) -> Data? {
        let cleanedDirect = cleanJSONString(text)
        if let data = cleanedDirect.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        if let startFence = text.range(of: "```json"),
           let endFence = text.range(of: "```", range: startFence.upperBound..<text.endIndex) {
            let jsonStr = cleanJSONString(String(text[startFence.upperBound..<endFence.lowerBound]))
            if let data = jsonStr.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        if let startFence = text.range(of: "```"),
           let endFence = text.range(of: "```", range: startFence.upperBound..<text.endIndex) {
            let jsonStr = cleanJSONString(String(text[startFence.upperBound..<endFence.lowerBound]))
            if let data = jsonStr.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        if let firstOpen = text.firstIndex(of: "{"),
           let lastClose = text.lastIndex(of: "}"),
           firstOpen < lastClose {
            let jsonStr = cleanJSONString(String(text[firstOpen...lastClose]))
            if let data = jsonStr.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        return nil
    }

    private func error(for availability: AIAvailability) -> AIProviderError {
        switch availability {
        case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
        case .deviceNotEligible: return .deviceNotEligible
        case .modelNotReady: return .modelNotReady
        case .unsupported, .unknown: return .unavailable
        case .available: return .unavailable
        }
    }

    private func unavailableError(for provider: any AIProvider) -> AIProviderError {
        if provider.availability == .unknown,
           (provider.kind == .anthropic || provider.kind == .openAI),
           provider.kind != .appleOnDevice {
            return .authenticationRequired
        }
        return error(for: provider.availability)
    }

    private func message(for error: AIProviderError) -> String {
        switch error {
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings to let me think locally."
        case .modelNotReady:
            return "I'm getting my local model ready. Try again in a moment."
        case .deviceNotEligible:
            return "Apple's on-device model isn't available on this Mac."
        case .authenticationRequired:
            return "Your AI provider needs a valid API key."
        case .unavailable:
            return "On-device AI is unavailable right now."
        case .cancelled:
            return "Okay — stopped."
        case .networkFailure:
            return "I can't reach that AI service right now."
        case .invalidResponse, .generationFailure:
            return "I couldn't finish that response. Please try again."
        }
    }

    func cancel() {
        requestTask?.cancel()
        requestTask = nil
        AmoraActionExecutionCoordinator.shared.cancelExecution()
        if state == .thinking {
            state = .cancelled
            AMORAEventCenter.shared.emit(.aiCancelled)
        }
    }

    func dismissResponse() {
        guard state != .thinking else { return }
        response = nil
        lastError = nil
        state = .idle
        AMORAContext.shared.dismissAIResponse()
    }

    func startNewConversation() {
        cancel()
        AmoraActionExecutionCoordinator.shared.reset()
        conversation.reset()
        AmoraConversationContextManager.shared.reset()
        response = nil
        state = .idle
        AMORAContext.shared.dismissAIResponse()
    }
}

/// The single routing seam between deterministic commands and optional AI.
@MainActor
final class AMORACommandGateway {
    let parser: AMORACommandParser
    let router: AMORACommandRouter
    let assistant: AssistantManager

    init(parser: AMORACommandParser = .init(), router: AMORACommandRouter = .shared, assistant: AssistantManager = .shared) {
        self.parser = parser; self.router = router; self.assistant = assistant
    }

    func submit(_ input: String, settings: AISettingsSnapshot) async -> AMORACommandResult {
        AmoraActionExecutionCoordinator.shared.reset()
        let isCompound = Self.isCompoundRequest(input)
        let normalized = AMORACommandParser.normalize(input)
        let isConfirmTest = normalized == "confirm test" || normalized == "test confirm" || normalized == "run confirmation test" || normalized == "test confirmation"

        if isConfirmTest {
            WindowManager.shared.showQuickPanel()
            let results = await AmoraActionEngine.shared.executeSequence([
                .confirmTest(actionName: "Test Action", prompt: "Are you sure you want to run this test action?")
            ])
            let answer = AmoraActionResult.combineMessages(from: results)
            let allSucceeded = results.allSatisfy { $0.status == .success }
            return allSucceeded ? .success(message: answer) : .failure(message: answer)
        }

        // 1. Direct Action Engine execution for multi-action compound requests (deterministic grammar)
        if isCompound, let directActions = Self.parseDeterministicActions(from: input) {
            WindowManager.shared.showQuickPanel()
            let convContext = settings.contextAwarenessEnabled ? AmoraConversationContextManager.shared.validContext() : nil
            let actionContext = AmoraActionContext(
                snapshot: settings.contextAwarenessEnabled ? AmoraContextProvider.shared.captureSnapshot() : nil,
                conversationContext: convContext
            )
            let results = await AmoraActionEngine.shared.executeSequence(directActions, context: actionContext)
            if settings.contextAwarenessEnabled {
                for act in directActions {
                    AmoraConversationContextManager.shared.recordAction(act, date: Date())
                }
            }
            let answer = AmoraActionResult.combineMessages(from: results)
            let allSucceeded = results.allSatisfy { $0.status == .success }
            return allSucceeded ? .success(message: answer) : .failure(message: answer)
        }

        // Ephemeral contextual follow-up evaluation (pronouns, omitted targets, modifications, etc.)
        if settings.contextAwarenessEnabled {
            let convContext = AmoraConversationContextManager.shared.validContext()
            let snapshot = AmoraContextProvider.shared.captureSnapshot()
            let resolution = AmoraContextualFollowUpResolver.shared.resolve(
                input: input,
                context: convContext,
                snapshot: snapshot,
                contextAwarenessEnabled: settings.contextAwarenessEnabled
            )
            switch resolution {
            case .ambiguous(let prompt, _):
                return .needsInformation(prompt: prompt)
            case .resolvedAction(let action):
                WindowManager.shared.showQuickPanel()
                let actionContext = AmoraActionContext(snapshot: snapshot, conversationContext: convContext)
                let results = await AmoraActionEngine.shared.executeSequence([action], context: actionContext)
                AmoraConversationContextManager.shared.recordAction(action, date: Date())
                let answer = AmoraActionResult.combineMessages(from: results)
                let allSucceeded = results.allSatisfy { $0.status == .success }
                return allSucceeded ? .success(message: answer) : .failure(message: answer)
            case .resolvedCommand(let cmd):
                let result = router.execute(cmd)
                AmoraConversationContextManager.shared.recordCommand(cmd, date: Date())
                return result
            case .unhandled:
                break
            }
        }

        var parseContext = router.currentContext()
        parseContext.contextAwarenessEnabled = settings.contextAwarenessEnabled
        let command = isCompound ? .unknown(text: input) : parser.parse(input, context: parseContext)

        // 2. If AI is enabled and genuinely available on-device, query assistant
        var shouldQueryAssistant = false
        if settings.enabled && assistant.providerAvailability == .available {
            let isContextQuestion = normalized.hasPrefix("how ") ||
                normalized.hasPrefix("what ") ||
                normalized.hasPrefix("is ") ||
                normalized.hasPrefix("which ") ||
                normalized.hasPrefix("who ") ||
                input.contains("?")
            if case let .unknown(text) = command, (isCompound || !isLocalUnknown(text)) {
                shouldQueryAssistant = true
            } else if isContextQuestion && command == .showBattery {
                shouldQueryAssistant = true
            }
        }
        if shouldQueryAssistant {
            WindowManager.shared.showQuickPanel()
            let answer = await assistant.submit(input, settings: settings)
            if assistant.state == .failed || assistant.state == .cancelled {
                return .failure(message: answer)
            }
            return .success(message: answer)
        }

        // 3. Fallback for AI or tools if supported
        if case let .unknown(text) = command, (isCompound || !isLocalUnknown(text)) {
            if let localResults = executeKnownToolSequence(input) {
                let message = localResults.map(\.message).joined(separator: " ")
                return .success(message: message)
            }
            WindowManager.shared.showQuickPanel()
            let answer = await assistant.submit(input, settings: settings)
            if assistant.state == .failed || assistant.state == .cancelled {
                return .failure(message: answer)
            }
            return .success(message: answer)
        }

        // 4. Default to router for single commands
        return router.execute(command)
    }

    static func isCompoundRequest(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.contains(",") { return true }
        if lower.contains(" and then ") { return true }
        if lower.contains(" then ") { return true }
        if lower.contains(" and ") { return true }
        if lower.contains(" & ") { return true }
        return false
    }

    static func parseDeterministicActions(from input: String) -> [AmoraAction]? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }

        // Bounded, deterministic separators:
        // 1. Comma with optional conjunction: ", and then ", ", then ", ", and ", ", & ", ", "
        // 2. Conjunction alone: " and then ", " then ", " and ", " & "
        let separatorPattern = #"(?:,\s*(?:and\s+then|then|and|&)\s*|,\s*|\s+(?:and\s+then|then|and|&)\s+)"#
        guard let regex = try? NSRegularExpression(pattern: separatorPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsString = trimmed as NSString
        let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return nil }

        struct RawSegment {
            var text: String
            var separatorToNext: String?
        }

        var segments: [RawSegment] = []
        var lastLocation = 0

        for match in matches {
            let segmentRange = NSRange(location: lastLocation, length: match.range.location - lastLocation)
            let segmentText = nsString.substring(with: segmentRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let sepText = nsString.substring(with: match.range)
            segments.append(RawSegment(text: segmentText, separatorToNext: sepText))
            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < nsString.length {
            let finalRange = NSRange(location: lastLocation, length: nsString.length - lastLocation)
            let finalSegmentText = nsString.substring(with: finalRange).trimmingCharacters(in: .whitespacesAndNewlines)
            segments.append(RawSegment(text: finalSegmentText, separatorToNext: nil))
        }

        segments.removeAll { $0.text.isEmpty }
        guard segments.count > 1 else { return nil }

        // Boundary merging: if a segment does NOT parse as a standalone action, merge it into the previous segment.
        // This keeps phrases containing "and" or commas (e.g. "Command and Conquer") intact.
        var i = 0
        while i < segments.count {
            if parseSingleAction(from: segments[i].text) != nil {
                i += 1
            } else {
                if i > 0 {
                    let sep = segments[i - 1].separatorToNext ?? " "
                    segments[i - 1].text = "\(segments[i - 1].text)\(sep)\(segments[i].text)"
                    segments[i - 1].separatorToNext = segments[i].separatorToNext
                    segments.remove(at: i)
                    i -= 1
                } else {
                    if segments.count > 1 {
                        let sep = segments[0].separatorToNext ?? " "
                        segments[1].text = "\(segments[0].text)\(sep)\(segments[1].text)"
                        segments.remove(at: 0)
                    } else {
                        return nil
                    }
                }
            }
        }

        guard segments.count > 1 else { return nil }

        var actions: [AmoraAction] = []
        for seg in segments {
            guard let action = parseSingleAction(from: seg.text) else {
                return nil
            }
            actions.append(action)
        }

        return actions.count > 1 ? actions : nil
    }

    static func parseSingleAction(from rawText: String) -> AmoraAction? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        // --- 1. Confirmation Test ---
        if lower == "confirm test" || lower == "test confirm" || lower == "run confirmation test" || lower == "test confirmation" {
            return .confirmTest(actionName: "Test Action", prompt: "Are you sure you want to run this test action?")
        }

        // --- 2. Workspace / Dashboard ---
        if lower == "open workspace" || lower == "show workspace" || lower == "workspace" ||
           lower == "open dashboard" || lower == "show dashboard" || lower == "dashboard" {
            return .openWorkspace()
        }

        // --- 3. Media Controls ---
        // Spotify specific playback:
        if lower == "play spotify" || lower == "start spotify" || lower == "resume spotify" {
            return .playMusic
        }
        if lower == "pause spotify" || lower == "stop spotify" {
            return .pauseMusic
        }
        if lower == "next spotify" || lower == "skip spotify" || lower == "next song spotify" || lower == "next track spotify" {
            return .nextTrack
        }
        if lower == "previous spotify" || lower == "previous song spotify" || lower == "previous track spotify" {
            return .previousTrack
        }

        // General media:
        if lower == "play music" || lower == "play the music" || lower == "play audio" || lower == "start music" || lower == "resume music" {
            return .playMusic
        }
        if lower == "pause music" || lower == "pause the music" || lower == "pause audio" || lower == "stop music" {
            return .pauseMusic
        }
        if lower == "next track" || lower == "next song" || lower == "skip track" || lower == "skip" {
            return .nextTrack
        }
        if lower == "previous track" || lower == "previous song" {
            return .previousTrack
        }

        // --- 4. Timer Controls ---
        if !lower.hasPrefix("open ") && !lower.hasPrefix("launch ") {
            if isTimerCancellation(lower) {
                return .cancelTimer
            }
            if lower == "pause the timer" || lower == "pause timer" || lower == "pause my timer" {
                return .pauseTimer
            }
            if lower == "resume the timer" || lower == "resume timer" || lower == "resume my timer" {
                return .resumeTimer
            }
            if lower.contains("timer") || lower.contains("pomodoro") || lower.contains("focus session") {
                if let duration = extractTimerDuration(from: lower) {
                    return .startTimer(duration: duration)
                }
            }
        }

        // --- 5. Folders ---
        if lower.hasPrefix("open ") || lower.hasPrefix("show ") {
            let folderCandidate = String(lower.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            switch folderCandidate {
            case "downloads", "download":
                return .openFolder(location: "downloads")
            case "documents", "document", "docs":
                return .openFolder(location: "documents")
            case "desktop":
                return .openFolder(location: "desktop")
            case "home":
                return .openFolder(location: "home")
            default:
                break
            }
        }

        // --- 6. Open Application ---
        if let appName = extractApplicationName(from: text, lower: lower) {
            return .openApplication(name: appName)
        }

        return nil
    }

    private static func isTimerCancellation(_ lower: String) -> Bool {
        let cancelPhrases = [
            "stop the timer", "stop my timer", "stop timer",
            "cancel the timer", "cancel my timer", "cancel timer",
            "end the timer", "end my timer", "end timer",
            "turn off the timer", "turn off my timer", "turn off timer",
            "clear the timer", "clear my timer", "clear timer",
            "stop it", "cancel it", "turn it off"
        ]
        return cancelPhrases.contains(lower)
    }

    private static func extractTimerDuration(from lower: String) -> TimeInterval? {
        let pattern = #"\b(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#
        guard let match = lower.range(of: pattern, options: .regularExpression) else {
            let parts = lower.split(separator: " ")
            if let last = parts.last, let val = Double(last), val > 0,
               (lower.hasPrefix("timer ") || lower.hasPrefix("start timer ") || lower.hasPrefix("start a timer ")) {
                return val * 60
            }
            return nil
        }
        let matchStr = String(lower[match])
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

    private static func extractApplicationName(from original: String, lower: String) -> String? {
        let prefixCount: Int
        if lower.hasPrefix("open application ") {
            prefixCount = 17
        } else if lower.hasPrefix("open app ") {
            prefixCount = 9
        } else if lower.hasPrefix("open ") {
            prefixCount = 5
        } else if lower.hasPrefix("launch ") {
            prefixCount = 7
        } else {
            return nil
        }

        let rawTarget = String(original.dropFirst(prefixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTarget.isEmpty else { return nil }
        let targetLower = rawTarget.lowercased()

        let reserved = ["downloads", "download", "documents", "document", "docs", "desktop", "home",
                        "workspace", "dashboard", "settings", "clipboard", "notes", "file shelf"]
        if reserved.contains(targetLower) { return nil }

        // Must NOT contain embedded command keywords (prevents command pollution)
        let forbiddenEmbedded = [
            "start spotify", "play spotify", "pause spotify",
            "start a ", "start timer", "stop timer", "cancel timer",
            "open workspace", "show workspace", "open dashboard",
            "open downloads", "open documents", "open desktop"
        ]
        if forbiddenEmbedded.contains(where: { targetLower.contains($0) }) {
            return nil
        }

        let cleanName = rawTarget.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}"))
        return cleanName.isEmpty ? nil : cleanName
    }

    /// Handles the small set of deterministic multi-tool combinations AMORA
    /// supports without spending an AI request on known local capabilities.
    private func executeKnownToolSequence(_ input: String) -> [AMORAToolResult]? {
        let text = AMORACommandParser.normalize(input)
        var requests: [AMORAToolRequest] = []
        if text.contains("timer"), let seconds = durationSeconds(in: text) {
            requests.append(.init(tool: .timer, operation: .startTimer(seconds: seconds)))
        }
        if text.contains("youtube") || text.contains("video") {
            if text.contains("pause") { requests.append(.init(tool: .browserMedia, operation: .pauseMedia)) }
            else if text.contains("play") { requests.append(.init(tool: .browserMedia, operation: .playMedia)) }
        }
        if text.contains("battery") { requests.append(.init(tool: .battery, operation: .readBattery)) }
        if (text.contains("what s playing") || text.contains("what is playing")) && !requests.contains(where: { $0.operation == .readMedia }) {
            requests.append(.init(tool: .music, operation: .readMedia))
        }
        guard requests.count > 1, requests.count <= AMORAToolRegistry.shared.maximumCallsPerRequest else { return nil }
        let results = requests.map { AMORAToolRegistry.shared.execute($0) }
        return results.allSatisfy { $0.status == .success || $0.status == .unsupported } ? results : results
    }

    private func durationSeconds(in text: String) -> Int? {
        let pattern = #"(\d+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: " ")
        guard let value = Int(parts[0]), let unit = parts.last else { return nil }
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") { return value * 3600 }
        if unit.hasPrefix("second") || unit.hasPrefix("sec") { return value }
        return value * 60
    }

    private func isLocalUnknown(_ text: String) -> Bool {
        if text.isEmpty || text == "open project" { return true }
        let isQuestion = text.contains("how much") ||
            text.contains("what is") ||
            text.contains("what's") ||
            text.contains("whats") ||
            text.contains("is my") ||
            text.contains("is there") ||
            text.contains("status") ||
            text.contains("remaining") ||
            text.contains("left") ||
            text.contains("?")
        if isQuestion {
            return false
        }
        return text.contains("timer") || text.contains("focus session") || text.contains("pomodoro")
    }
}
