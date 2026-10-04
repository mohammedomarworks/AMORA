import Foundation
import Observation

enum AssistantState: Equatable, Sendable { case idle, thinking, responding, failed, cancelled }

@Observable @MainActor
final class AssistantManager {
    static let shared = AssistantManager(provider: UnavailableAIProvider(kind: .local), providerIsInjected: false)

    private var provider: any AIProvider
    private let providerIsInjected: Bool
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

        var messages = conversation.messages
        messages.append(AIMessage(role: .user, content: "[AMORA tool policy] You may request only approved tools by returning strict JSON {\"calls\":[{\"tool\":\"...\",\"action\":\"...\",\"seconds\":null,\"text\":null,\"name\":null}]}. Approved tools: battery read; timer start/pause/resume/stop/add; music or browserMedia read/play/pause/next/previous; notes create/list; system read; application open; folder open; view show. Never request shell commands, arbitrary paths, unknown tools, or destructive actions. If no tool is needed, answer normally."))
        if let context = AIContextComposer.relevantContext(for: input) {
            messages.append(AIMessage(role: .user, content: "[System context]\n\(context)"))
        }
        let userMessage = AIMessage(role: .user, content: input)
        messages.append(userMessage)
        conversation.append(userMessage)

        do {
            let rawAnswer = try await provider.send(messages: messages, model: settings.model, apiKey: settings.apiKey)
            try Task.checkCancellation()
            let answer: String
            if let plan = try? JSONDecoder().decode(AMORAToolPlan.self, from: Data(rawAnswer.utf8)),
               let requests = plan.requests() {
                let results = requests.map { AMORAToolRegistry.shared.execute($0) }
                if let confirmation = results.first(where: { $0.status == .needsConfirmation }) {
                    answer = "I need your confirmation before I do that. \(confirmation.message)"
                } else {
                    answer = results.map(\.message).joined(separator: " ")
                }
            } else {
                answer = rawAnswer
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
        conversation.reset()
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
        let command = parser.parse(input, context: router.currentContext())
        if case let .unknown(text) = command, !isLocalUnknown(text) {
            if let localResults = executeKnownToolSequence(input) {
                let message = localResults.map(\.message).joined(separator: " ")
                return .success(message: message)
            }
            WindowManager.shared.showQuickPanel()
            return .success(message: await assistant.submit(input, settings: settings))
        }
        return router.execute(command)
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
        text.isEmpty || text.contains("timer") || text.contains("focus session") || text.contains("pomodoro") || text == "open project"
    }
}
