import Cocoa
import Foundation

@MainActor
final class NotchManager {
    private weak var window: NSWindow?
    private weak var screen: NSScreen?
    private var cursorTimer: Timer?
    private var lastCursorPosition: CGPoint = .zero

    init(window: NSWindow, screen: NSScreen) {
        self.window = window
        self.screen = screen
        setupCursorTracking()
    }

    func stopTracking() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    static var notchedScreen: NSScreen? {
        for screen in NSScreen.screens {
            if screen.safeAreaInsets.top > 0 {
                return screen
            }
        }
        return NSScreen.main
    }

    static func notchRect(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let safeAreaTop = screen.safeAreaInsets.top

        if safeAreaTop > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           rightArea.minX > leftArea.maxX {
            let width = rightArea.minX - leftArea.maxX
            let height = safeAreaTop
            let originX = leftArea.maxX
            let originY = screenFrame.maxY - height
            return NSRect(x: originX, y: originY, width: width, height: height)
        }

        // Fallback for displays without a hardware notch (e.g., external monitor or older Mac)
        let fallbackWidth: CGFloat = 200
        let fallbackHeight: CGFloat = safeAreaTop > 0 ? safeAreaTop : 34
        let originX = screenFrame.midX - (fallbackWidth / 2)
        let originY = screenFrame.maxY - fallbackHeight

        return NSRect(x: originX, y: originY, width: fallbackWidth, height: fallbackHeight)
    }

    private func setupCursorTracking() {
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.trackCursor()
            }
        }
    }

    private func trackCursor() {
        guard let window = self.window, window.isVisible else { return }
        let currentPosition = NSEvent.mouseLocation

        if currentPosition != lastCursorPosition {
            let deltaX = currentPosition.x - lastCursorPosition.x
            let deltaY = currentPosition.y - lastCursorPosition.y

            if abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
                handleCursorMovement(deltaX: deltaX, deltaY: deltaY)
                lastCursorPosition = currentPosition
            }

            let windowFrame = window.frame
            let distance = hypot(currentPosition.x - windowFrame.midX, currentPosition.y - windowFrame.midY)

            let stateManager = AppState.shared.stateManager
            let settings = AppState.shared.settings

            if distance < 60 {
                if stateManager.currentState == .idle || stateManager.currentState == .watching {
                    if settings.hoverToExpand {
                        stateManager.transition(to: .hover)
                    } else {
                        stateManager.transition(to: .watching)
                    }
                }
            } else if distance < 200 {
                if stateManager.currentState == .idle {
                    stateManager.transition(to: .watching)
                }
            } else {
                if stateManager.currentState == .hover || stateManager.currentState == .watching {
                    stateManager.transition(to: .idle)
                }
            }
        }
    }

    private func handleCursorMovement(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = self.window else { return }
        let windowFrame = window.frame
        let cursorPos = NSEvent.mouseLocation

        let halfWidth = max(windowFrame.width / 2, 1)
        let halfHeight = max(windowFrame.height / 2, 1)
        let relX = (cursorPos.x - windowFrame.midX) / halfWidth
        let relY = (cursorPos.y - windowFrame.midY) / halfHeight

        let normalizedX = max(-1.0, min(1.0, Double(relX)))
        let normalizedY = max(-1.0, min(1.0, Double(relY)))

        NotificationCenter.default.post(
            name: .cursorMoved,
            object: nil,
            userInfo: [
                "deltaX": Double(deltaX),
                "deltaY": Double(deltaY),
                "normalizedX": normalizedX,
                "normalizedY": normalizedY
            ]
        )
    }
}

extension Notification.Name {
    static let cursorMoved = Notification.Name("AMORACursorMoved")
}
