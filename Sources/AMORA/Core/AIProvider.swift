import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIProviderKind: String, CaseIterable, Codable, Sendable {
    case appleOnDevice = "apple-on-device"
    case anthropic
    case openAI = "openai"
    case local
    case none
}

enum AIProviderError: Error, Equatable, Sendable {
    case unavailable
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case authenticationRequired
    case cancelled
    case invalidResponse
    case networkFailure
    case generationFailure
}

enum AIAvailability: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unsupported
    case unknown
}

extension AIAvailability {
    var displayName: String {
        switch self {
        case .available: return "Available"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence Not Enabled"
        case .deviceNotEligible: return "Device Not Eligible"
        case .modelNotReady: return "Model Not Ready"
        case .unsupported: return "Unsupported on this macOS version"
        case .unknown: return "Unknown"
        }
    }
}

struct AIMessage: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    init(role: Role, content: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Provider-neutral boundary. Providers receive only the bounded conversation
/// and explicitly selected local context supplied by AssistantManager.
protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    var isAvailable: Bool { get }
    var availability: AIAvailability { get }
    func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String
}

extension AIProvider {
    var availability: AIAvailability { isAvailable ? .available : .unknown }
}

struct UnavailableAIProvider: AIProvider {
    let kind: AIProviderKind
    let availability: AIAvailability
    var isAvailable: Bool { false }

    init(kind: AIProviderKind, availability: AIAvailability = .unknown) {
        self.kind = kind
        self.availability = availability
    }

    func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
        throw AIProviderError.unavailable
    }
}

/// A deterministic provider used by tests and previews. It never performs I/O.
struct MockAIProvider: AIProvider {
    let kind: AIProviderKind = .local
    let response: String
    var isAvailable: Bool { true }

    init(response: String = "Hello! I'm AMORA.") { self.response = response }

    func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
        try Task.checkCancellation()
        return response
    }
}

struct AISettingsSnapshot: Sendable {
    let enabled: Bool
    let provider: AIProviderKind
    let model: String
    let apiKey: String?
    let contextAwarenessEnabled: Bool
    let memoryEnabled: Bool

    init(
        enabled: Bool,
        provider: AIProviderKind,
        model: String,
        apiKey: String?,
        contextAwarenessEnabled: Bool = true,
        memoryEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.contextAwarenessEnabled = contextAwarenessEnabled
        self.memoryEnabled = memoryEnabled
    }
}

struct HTTPAIProvider: AIProvider {
    let kind: AIProviderKind
    let endpoint: URL
    var isAvailable: Bool { true }

    func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw AIProviderError.unavailable }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = ["model": model, "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIProviderError.networkFailure }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { throw AIProviderError.invalidResponse }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError { throw CancellationError() }
          catch let error as AIProviderError { throw error }
          catch { throw AIProviderError.networkFailure }
    }
}

struct AnthropicAIProvider: AIProvider {
    let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    let kind: AIProviderKind = .anthropic
    var isAvailable: Bool { true }

    func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw AIProviderError.unavailable }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let payload: [String: Any] = ["model": model, "max_tokens": 1024,
                                      "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIProviderError.networkFailure }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = root["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else { throw AIProviderError.invalidResponse }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError { throw CancellationError() }
          catch let error as AIProviderError { throw error }
          catch { throw AIProviderError.networkFailure }
    }
}

#if canImport(FoundationModels)
/// Native, on-device AMORA conversation provider. Foundation Models types are
/// intentionally kept behind this provider-neutral boundary.
@available(macOS 26.0, *)
struct AppleFoundationModelProvider: AIProvider {
    let kind: AIProviderKind = .appleOnDevice
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    static var currentAvailability: AIAvailability {
        map(model: .default)
    }

    var availability: AIAvailability { Self.map(model: model) }
    var isAvailable: Bool { availability == .available }

    func send(messages: [AIMessage], model _: String, apiKey _: String?) async throws -> String {
        switch availability {
        case .available:
            break
        case .appleIntelligenceNotEnabled:
            throw AIProviderError.appleIntelligenceNotEnabled
        case .deviceNotEligible:
            throw AIProviderError.deviceNotEligible
        case .modelNotReady:
            throw AIProviderError.modelNotReady
        case .unsupported, .unknown:
            throw AIProviderError.unavailable
        }

        try Task.checkCancellation()
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let prompt = messages.map { "\($0.role == .user ? "User" : "AMORA"): \($0.content)" }
            .joined(separator: "\n")
        do {
            let response = try await session.respond(to: prompt)
            try Task.checkCancellation()
            let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw AIProviderError.invalidResponse }
            return answer
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.generationFailure
        }
    }

    private static let instructions = """
    You are AMORA, a friendly, calm, concise Mac companion. Be helpful and slightly playful, but not childish. Answer as AMORA. Prefer short, clear explanations and do not claim to have performed actions unless the app explicitly confirms them.
    """

    private static func map(model: SystemLanguageModel) -> AIAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .deviceNotEligible: return .deviceNotEligible
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown
            }
        }
    }
}
#endif

enum AIProviderFactory {
    static func make(for settings: AISettingsSnapshot) -> any AIProvider {
        guard settings.enabled else { return UnavailableAIProvider(kind: settings.provider) }
        switch settings.provider {
        case .appleOnDevice:
            if #available(macOS 26.0, *) {
                #if canImport(FoundationModels)
                return AppleFoundationModelProvider()
                #else
                return UnavailableAIProvider(kind: .appleOnDevice, availability: .unsupported)
                #endif
            }
            return UnavailableAIProvider(kind: .appleOnDevice, availability: .unsupported)
        case .openAI:
            guard settings.apiKey?.isEmpty == false else { return UnavailableAIProvider(kind: .openAI) }
            return HTTPAIProvider(kind: .openAI, endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!)
        case .anthropic:
            guard settings.apiKey?.isEmpty == false else { return UnavailableAIProvider(kind: .anthropic) }
            return AnthropicAIProvider()
        case .local, .none:
            return UnavailableAIProvider(kind: settings.provider)
        }
    }
}
