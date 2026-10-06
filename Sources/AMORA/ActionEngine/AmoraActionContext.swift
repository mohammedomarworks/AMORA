import Foundation

/// Execution context passed into Action Engine invocations.
public struct AmoraActionContext: Equatable, Sendable {
    public var isConfirmed: Bool
    public var caller: String?
    public var metadata: [String: String]
    public var timestamp: Date

    public init(
        isConfirmed: Bool = false,
        caller: String? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.isConfirmed = isConfirmed
        self.caller = caller
        self.metadata = metadata
        self.timestamp = timestamp
    }
}
