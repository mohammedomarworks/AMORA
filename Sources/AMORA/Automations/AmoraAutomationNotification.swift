import Foundation

/// Represents an active user-facing notification produced by an AMORA automation.
/// Displayed directly in the Dynamic Island companion panel underneath the AMORA mascot.
public struct AmoraAutomationNotification: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let automationId: UUID?
    public let automationName: String?
    public let triggerIcon: String
    public let triggerName: String
    public let message: String
    public let action: AmoraAction?
    public let actionTitle: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        automationId: UUID? = nil,
        automationName: String? = nil,
        triggerIcon: String = "bell.badge",
        triggerName: String = "Automation",
        message: String,
        action: AmoraAction? = nil,
        actionTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.automationId = automationId
        self.automationName = automationName
        self.triggerIcon = triggerIcon
        self.triggerName = triggerName
        self.message = message
        self.action = action
        self.actionTitle = actionTitle
        self.createdAt = createdAt
    }
}
