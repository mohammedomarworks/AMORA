import Foundation
import Observation

/// The high-level state of the AMORA Action Execution pipeline.
public enum AmoraActionExecutionState: String, Codable, Equatable, Sendable {
    case idle
    case thinking
    case executing
    case completed
    case failed
    case awaitingConfirmation
}

/// The status of an individual action within an execution plan.
public enum AmoraActionItemStatus: String, Codable, Equatable, Sendable {
    case pending
    case executing
    case completed
    case failed
    case awaitingConfirmation
    case cancelled
}

/// A representation of a single action within an active or completed execution sequence.
public struct AmoraActionExecutionItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let action: AmoraAction
    public var status: AmoraActionItemStatus
    public var title: String
    public var message: String?
    public var result: AmoraActionResult?

    public init(
        id: UUID = UUID(),
        action: AmoraAction,
        status: AmoraActionItemStatus = .pending,
        title: String? = nil,
        message: String? = nil,
        result: AmoraActionResult? = nil
    ) {
        self.id = id
        self.action = action
        self.status = status
        self.title = title ?? action.humanReadableName
        self.message = message
        self.result = result
    }
}

/// Represents an active request for user confirmation before executing a potentially sensitive action.
public struct AmoraPendingConfirmation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let action: AmoraAction
    public let prompt: String

    public init(id: UUID = UUID(), action: AmoraAction, prompt: String) {
        self.id = id
        self.action = action
        self.prompt = prompt
    }
}

/// Observable coordinator managing live action-execution state, progress, confirmation, and cancellation.
@Observable @MainActor
public final class AmoraActionExecutionCoordinator: Sendable {
    public static let shared = AmoraActionExecutionCoordinator()

    public private(set) var state: AmoraActionExecutionState = .idle
    public private(set) var items: [AmoraActionExecutionItem] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var activeExecutionId: UUID? = nil
    public private(set) var summaryMessage: String? = nil
    public private(set) var pendingConfirmation: AmoraPendingConfirmation? = nil
    public private(set) var isCancelled: Bool = false

    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    public init() {}

    public var totalCount: Int {
        items.count
    }

    public var currentItem: AmoraActionExecutionItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    /// Resets the coordinator back to idle state.
    public func reset() {
        if let cont = confirmationContinuation {
            confirmationContinuation = nil
            cont.resume(returning: false)
        }
        state = .idle
        items = []
        currentIndex = 0
        activeExecutionId = nil
        summaryMessage = nil
        pendingConfirmation = nil
        isCancelled = false
    }

    /// Transitions to the thinking state before an action plan is resolved.
    public func beginThinking() {
        reset()
        state = .thinking
        activeExecutionId = UUID()
    }

    /// Begins execution of a sequence of actions.
    public func beginSequence(_ actions: [AmoraAction]) {
        if let cont = confirmationContinuation {
            confirmationContinuation = nil
            cont.resume(returning: false)
        }
        isCancelled = false
        currentIndex = 0
        activeExecutionId = UUID()
        pendingConfirmation = nil
        summaryMessage = nil
        items = actions.map { AmoraActionExecutionItem(action: $0, status: .pending) }
        state = actions.isEmpty ? .idle : .executing
    }

    /// Marks the item at the given index as actively executing.
    public func willExecuteItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        currentIndex = index
        items[index].status = .executing
        state = .executing
    }

    /// Requests user confirmation for an action and awaits response.
    public func requestConfirmation(for action: AmoraAction, prompt: String, at index: Int) async -> Bool {
        guard index >= 0 && index < items.count else { return false }
        currentIndex = index
        items[index].status = .awaitingConfirmation
        state = .awaitingConfirmation
        let request = AmoraPendingConfirmation(action: action, prompt: prompt)
        pendingConfirmation = request

        return await withCheckedContinuation { continuation in
            self.confirmationContinuation = continuation
        }
    }

    /// Confirms the active pending action.
    public func confirmPendingAction() {
        guard let continuation = confirmationContinuation else { return }
        confirmationContinuation = nil
        pendingConfirmation = nil
        state = .executing
        continuation.resume(returning: true)
    }

    /// Cancels the active pending action.
    public func cancelPendingAction() {
        guard let continuation = confirmationContinuation else { return }
        confirmationContinuation = nil
        pendingConfirmation = nil
        if currentIndex >= 0 && currentIndex < items.count {
            items[currentIndex].status = .cancelled
        }
        continuation.resume(returning: false)
    }

    /// Cancels the ongoing action execution sequence.
    public func cancelExecution() {
        isCancelled = true
        if let continuation = confirmationContinuation {
            confirmationContinuation = nil
            pendingConfirmation = nil
            continuation.resume(returning: false)
        }
        // Mark all remaining pending or executing items as cancelled
        for i in 0..<items.count {
            if items[i].status == .pending || items[i].status == .executing || items[i].status == .awaitingConfirmation {
                items[i].status = .cancelled
            }
        }
        state = .failed
        summaryMessage = "Action execution stopped."
    }

    /// Records completion of an individual action.
    public func didCompleteItem(at index: Int, result: AmoraActionResult) {
        guard index >= 0 && index < items.count else { return }
        items[index].status = .completed
        items[index].result = result
        items[index].message = result.message
    }

    /// Records failure of an individual action.
    public func didFailItem(at index: Int, result: AmoraActionResult) {
        guard index >= 0 && index < items.count else { return }
        items[index].status = .failed
        items[index].result = result
        items[index].message = result.message
    }

    /// Records cancellation of an individual action.
    public func didCancelItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items[index].status = .cancelled
    }

    /// Completes the sequence with an aggregated summary message.
    public func finishSequence(results: [AmoraActionResult], summary: String? = nil) {
        if isCancelled {
            state = .failed
            return
        }
        summaryMessage = summary ?? AmoraActionResult.combineMessages(from: results)
        let hasFailures = results.contains(where: { $0.status != .success })
        state = hasFailures ? .failed : .completed
    }
}
