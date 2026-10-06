import Foundation
import CoreGraphics

/// Evaluates outside mouse interactions (mouseDown, mouseDragged, mouseUp) to distinguish
/// ordinary outside clicks (which dismiss AMORA) from external file/folder drag gestures
/// (which must keep AMORA visible and open so drops into File Shelf succeed).
public final class OutsideDismissalManager: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case pendingOutsideClick(startPoint: CGPoint, timestamp: CFTimeInterval)
        case externalDrag(startPoint: CGPoint, timestamp: CFTimeInterval)
    }

    public enum Action: Equatable, Sendable {
        case none
        case dismiss
    }

    public private(set) var state: State = .idle
    public let dragThreshold: CGFloat

    public var isExternalDragInProgress: Bool {
        if case .externalDrag = state { return true }
        return false
    }

    public var isPendingOutsideClick: Bool {
        if case .pendingOutsideClick = state { return true }
        return false
    }

    public init(dragThreshold: CGFloat = 8.0) {
        self.dragThreshold = dragThreshold
    }

    public func reset() {
        state = .idle
    }

    /// Handles a mouseDown event.
    /// If outside the window, enters `pendingOutsideClick` without dismissing.
    @discardableResult
    public func handleMouseDown(at point: CGPoint, isInsideWindow: Bool, timestamp: CFTimeInterval = 0) -> Action {
        if isInsideWindow {
            state = .idle
            return .none
        }
        state = .pendingOutsideClick(startPoint: point, timestamp: timestamp)
        return .none
    }

    /// Handles a mouseDragged event or movement update.
    /// If currently pending an outside click and movement reaches or exceeds `dragThreshold`,
    /// promotes the state to `externalDrag` so AMORA remains open.
    @discardableResult
    public func handleMouseDragged(to point: CGPoint, isInsideWindow: Bool, timestamp: CFTimeInterval = 0) -> Action {
        switch state {
        case .idle:
            return .none

        case .pendingOutsideClick(let startPoint, let t0):
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if distance >= dragThreshold {
                state = .externalDrag(startPoint: startPoint, timestamp: t0)
            }
            return .none

        case .externalDrag:
            return .none
        }
    }

    /// Handles a mouseUp event.
    /// - If in `pendingOutsideClick` and movement < dragThreshold and outside window: returns `.dismiss`.
    /// - If in `externalDrag` or movement >= dragThreshold: returns `.none` (clears state, keeps AMORA open).
    @discardableResult
    public func handleMouseUp(at point: CGPoint, isInsideWindow: Bool, timestamp: CFTimeInterval = 0) -> Action {
        switch state {
        case .idle:
            return .none

        case .pendingOutsideClick(let startPoint, _):
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            state = .idle
            if !isInsideWindow && distance < dragThreshold {
                return .dismiss
            } else {
                return .none
            }

        case .externalDrag:
            state = .idle
            return .none
        }
    }

    /// Checks whether the current pointer location has moved beyond `dragThreshold` while in `pendingOutsideClick`.
    @discardableResult
    public func checkMovement(at point: CGPoint) -> State {
        if case .pendingOutsideClick(let startPoint, let t0) = state {
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if distance >= dragThreshold {
                state = .externalDrag(startPoint: startPoint, timestamp: t0)
            }
        }
        return state
    }
}
