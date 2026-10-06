import Foundation

/// Structured outcome status for Action Engine executions.
public enum AmoraActionResultStatus: String, Codable, Equatable, Sendable {
    case success
    case unavailable
    case notPermitted
    case invalidInput
    case failed
    case needsConfirmation
}

/// Structured, rich result produced by every Action Engine execution.
public struct AmoraActionResult: Equatable, Sendable {
    public let actionId: String
    public let status: AmoraActionResultStatus
    public let message: String
    public let data: [String: String]
    public let executionID: UUID
    public let timestamp: Date

    public init(
        actionId: String,
        status: AmoraActionResultStatus,
        message: String,
        data: [String: String] = [:],
        executionID: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.actionId = actionId
        self.status = status
        self.message = message
        self.data = data
        self.executionID = executionID
        self.timestamp = timestamp
    }

    public static func success(
        actionId: String,
        message: String,
        data: [String: String] = [:]
    ) -> AmoraActionResult {
        .init(actionId: actionId, status: .success, message: message, data: data)
    }

    public static func unavailable(
        actionId: String,
        message: String,
        data: [String: String] = [:]
    ) -> AmoraActionResult {
        .init(actionId: actionId, status: .unavailable, message: message, data: data)
    }

    public static func notPermitted(
        actionId: String,
        message: String,
        data: [String: String] = [:]
    ) -> AmoraActionResult {
        .init(actionId: actionId, status: .notPermitted, message: message, data: data)
    }

    public static func invalidInput(
        actionId: String,
        message: String,
        data: [String: String] = [:]
    ) -> AmoraActionResult {
        .init(actionId: actionId, status: .invalidInput, message: message, data: data)
    }

    public static func failed(
        actionId: String,
        message: String,
        data: [String: String] = [:]
    ) -> AmoraActionResult {
        .init(actionId: actionId, status: .failed, message: message, data: data)
    }

    public static func needsConfirmation(
        actionId: String,
        prompt: String,
        data: [String: String] = [:]
    ) -> AmoraActionResult {
        .init(actionId: actionId, status: .needsConfirmation, message: prompt, data: data)
    }
}

/// Validation result produced prior to action execution.
public enum AmoraActionValidationResult: Equatable, Sendable {
    case valid
    case invalid(reason: String)
    case requiresConfirmation(prompt: String)
}

/// Confirmation requirement definition for an action capability.
public enum AmoraActionConfirmationRequirement: Equatable, Sendable {
    case notRequired
    case required(prompt: String)
}
