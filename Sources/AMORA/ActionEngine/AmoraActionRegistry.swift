import Foundation

/// Metadata describing a registered capability in AMORA.
public struct AmoraActionDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let isConfirmationRequired: Bool

    public init(
        id: String,
        name: String,
        description: String,
        isConfirmationRequired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isConfirmationRequired = isConfirmationRequired
    }
}

/// Execution definition for an action in the Action Engine.
@MainActor
public struct AmoraActionDefinition: Sendable {
    public let identifier: String
    public let name: String
    public let description: String
    public let isConfirmationRequiredByDefault: Bool
    public let confirmationRequirement: @MainActor @Sendable (AmoraAction) -> AmoraActionConfirmationRequirement
    public let validator: @MainActor @Sendable (AmoraAction) -> AmoraActionValidationResult
    public let handler: @MainActor @Sendable (AmoraAction, AmoraActionContext) async -> AmoraActionResult

    public init(
        identifier: String,
        name: String,
        description: String,
        isConfirmationRequiredByDefault: Bool = false,
        confirmationRequirement: @escaping @MainActor @Sendable (AmoraAction) -> AmoraActionConfirmationRequirement = { _ in .notRequired },
        validator: @escaping @MainActor @Sendable (AmoraAction) -> AmoraActionValidationResult = { _ in .valid },
        handler: @escaping @MainActor @Sendable (AmoraAction, AmoraActionContext) async -> AmoraActionResult
    ) {
        self.identifier = identifier
        self.name = name
        self.description = description
        self.isConfirmationRequiredByDefault = isConfirmationRequiredByDefault
        self.confirmationRequirement = confirmationRequirement
        self.validator = validator
        self.handler = handler
    }

    public var descriptor: AmoraActionDescriptor {
        AmoraActionDescriptor(
            id: identifier,
            name: name,
            description: description,
            isConfirmationRequired: isConfirmationRequiredByDefault
        )
    }
}

/// Central registry managing all available AMORA capabilities.
@MainActor
public final class AmoraActionRegistry: Sendable {
    private var definitions: [String: AmoraActionDefinition] = [:]

    public init() {}

    public func register(_ definition: AmoraActionDefinition) {
        definitions[definition.identifier] = definition
    }

    public func unregister(identifier: String) {
        definitions.removeValue(forKey: identifier)
    }

    public func definition(for identifier: String) -> AmoraActionDefinition? {
        definitions[identifier]
    }

    public func isRegistered(identifier: String) -> Bool {
        definitions[identifier] != nil
    }

    public var allDescriptors: [AmoraActionDescriptor] {
        definitions.values.map(\.descriptor).sorted(by: { $0.id < $1.id })
    }

    public var registeredIdentifiers: [String] {
        Array(definitions.keys).sorted()
    }
}
