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
        if let context = AIContextComposer.relevantContext(for: input) {
            messages.append(AIMessage(role: .user, content: "[System context]\n\(context)"))
        }
        let userMessage = AIMessage(role: .user, content: input)
        messages.append(userMessage)
        conversation.append(userMessage)

        do {
            let answer = try await provider.send(messages: messages, model: settings.model, apiKey: settings.apiKey)
            try Task.checkCancellation()
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
            WindowManager.shared.showQuickPanel()
            return .success(message: await assistant.submit(input, settings: settings))
        }
        return router.execute(command)
    }

    private func isLocalUnknown(_ text: String) -> Bool {
        text.isEmpty || text.contains("timer") || text.contains("focus session") || text.contains("pomodoro") || text == "open project"
    }
}
