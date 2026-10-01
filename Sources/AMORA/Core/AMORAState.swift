import Foundation
import Observation

enum AMORAState: String, CaseIterable, Codable, Sendable {
    case idle
    case watching
    case hover
    case expanded
    case thinking
    case happy
    case sleepy
    case alert
    case music
    case speaking
    case error

    var priority: Int {
        switch self {
        case .error: return 100
        case .thinking: return 90
        case .speaking: return 85
        case .alert: return 80
        case .expanded: return 70
        case .hover: return 60
        case .music: return 50
        case .happy: return 40
        case .watching: return 30
        case .sleepy: return 20
        case .idle: return 10
        }
    }

    func canTransition(to other: AMORAState) -> Bool {
        guard other != self else { return false }
        return other.priority > self.priority || (self != .idle && other.priority <= self.priority)
    }
}

@MainActor
protocol AMORAStateDelegate: AnyObject {
    func stateDidChange(from oldState: AMORAState, to newState: AMORAState)
}

@Observable @MainActor
final class AMORAStateManager {
    static let shared = AMORAStateManager()

    var currentState: AMORAState = .idle {
        didSet {
            guard oldValue != currentState else { return }
            delegate?.stateDidChange(from: oldValue, to: currentState)
        }
    }

    weak var delegate: AMORAStateDelegate?

    init() {}

    func setDelegate(_ delegate: AMORAStateDelegate) {
        self.delegate = delegate
    }

    func transition(to newState: AMORAState) {
        guard currentState.canTransition(to: newState) || newState.priority > currentState.priority else { return }
        currentState = newState
    }

    func resetToIdle() {
        currentState = .idle
    }
}
