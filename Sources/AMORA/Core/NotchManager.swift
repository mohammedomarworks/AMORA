import Cocoa
import Foundation

/// Represents the adaptive polling frequency tiers for cursor tracking.
enum CursorTrackingTier: String, CaseIterable, Equatable, Sendable {
    /// High-frequency tracking when cursor is near the notch (< 250 pt) or island is expanded.
    /// Provides 20 Hz (0.05s) responsiveness for smooth gaze tracking and immediate hover (< 60 pt).
    case active = "active"

    /// Moderate-frequency tracking in the approaching buffer zone (250..<450 pt).
    /// Runs at ~8.3 Hz (0.12s) to smoothly promote to `.active` as pointer moves closer.
    case approaching = "approaching"

    /// Low-frequency tracking when cursor is far from notch (>= 450 pt) and moving.
    /// Runs at ~3.3 Hz (0.30s), reducing CPU wakeups while tracking motion.
    case distant = "distant"

    /// Minimal-frequency tracking when cursor is far from notch (>= 450 pt) and stationary.
    /// Runs at 1.0 Hz (1.0s), saving 95% of idle main-thread timer wakeups.
    case idle = "idle"

    /// Suspended: timer is nil and event monitors are inactive.
    /// Used when window is hidden, minimized, displays are asleep, or tracking is paused/stopped.
    case suspended = "suspended"

    var interval: TimeInterval? {
        switch self {
        case .active: return 0.05       // 20 Hz
        case .approaching: return 0.12  // ~8.3 Hz
        case .distant: return 0.30      // ~3.3 Hz
        case .idle: return 1.00         // 1.0 Hz
        case .suspended: return nil     // 0 Hz
        }
    }

    var frequencyHz: Double {
        guard let interval, interval > 0 else { return 0.0 }
        return (1.0 / interval).rounded()
    }
}

@MainActor
final class NotchManager {
    private weak var window: NSWindow?
    private weak var screen: NSScreen?
    private var cursorTimer: Timer?
    private var lastCursorPosition: CGPoint = .zero

    private(set) var currentTier: CursorTrackingTier = .suspended
    private(set) var isTrackingEnabled: Bool = true
    private(set) var stationaryTicks: Int = 0
    private(set) var lastObservedDistance: CGFloat = .infinity

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    private var screenChangeObserver: Any?
    private var windowOcclusionObserver: Any?

    init(window: NSWindow, screen: NSScreen) {
        self.window = window
        self.screen = screen
        self.lastCursorPosition = NSEvent.mouseLocation
        setupTrackingLifecycle()
    }

    isolated deinit {
        stopTracking()
    }

    var hasEventMonitors: Bool {
        globalMouseMonitor != nil || localMouseMonitor != nil
    }

    var isTimerActive: Bool {
        cursorTimer?.isValid == true
    }

    var activeTimerInterval: TimeInterval? {
        guard let timer = cursorTimer, timer.isValid else { return nil }
        return timer.timeInterval
    }

    func pauseTracking() {
        isTrackingEnabled = false
        invalidateTimer()
        removeEventMonitors()
        currentTier = .suspended
    }

    func resumeTracking() {
        guard !isTrackingEnabled || currentTier == .suspended else { return }
        isTrackingEnabled = true
        installEventMonitors()
        if let window, window.isVisible {
            setTrackingTier(.active)
            trackCursor()
        } else {
            setTrackingTier(.idle)
        }
    }

    func stopTracking() {
        isTrackingEnabled = false
        invalidateTimer()
        removeEventMonitors()
        removeLifecycleObservers()
        currentTier = .suspended
    }

    func updateScreen(_ newScreen: NSScreen) {
        self.screen = newScreen
        if isTrackingEnabled {
            trackCursor()
        }
    }

    static var notchedScreen: NSScreen? {
        NSScreen.screens.first(where: { hasHardwareNotch(on: $0) }) ?? NSScreen.main
    }

    static func hasHardwareNotch(on screen: NSScreen) -> Bool {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return false }
        return rightArea.minX > leftArea.maxX
    }

    static func notchRect(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let safeAreaTop = screen.safeAreaInsets.top

        if hasHardwareNotch(on: screen),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           rightArea.minX > leftArea.maxX {
            let width = rightArea.minX - leftArea.maxX
            let height = safeAreaTop
            let originX = leftArea.maxX
            // Use the physical display top, not visibleFrame.maxY. The latter
            // represents usable application space below the menu bar.
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

    static func logGeometryIfEnabled(for screen: NSScreen, notchRect: NSRect, amoraFrame: NSRect) {
        guard UserDefaults.standard.bool(forKey: "AMORADebugGeometry") else { return }
        print("[AMORA] screen.frame=\(screen.frame)")
        print("[AMORA] screen.visibleFrame=\(screen.visibleFrame)")
        print("[AMORA] safeAreaInsets=\(screen.safeAreaInsets)")
        print("[AMORA] auxiliaryTopLeftArea=\(String(describing: screen.auxiliaryTopLeftArea))")
        print("[AMORA] auxiliaryTopRightArea=\(String(describing: screen.auxiliaryTopRightArea))")
        print("[AMORA] calculated notchRect=\(notchRect)")
        print("[AMORA] calculated AMORA frame=\(amoraFrame)")
    }

    private func setupTrackingLifecycle() {
        installLifecycleObservers()
        installEventMonitors()
        setTrackingTier(.active)
        if let window, window.isVisible {
            trackCursor()
        }
    }

    func setTrackingTier(_ tier: CursorTrackingTier) {
        currentTier = tier
        rescheduleTimer(for: tier)
    }

    private func rescheduleTimer(for tier: CursorTrackingTier) {
        invalidateTimer()
        guard isTrackingEnabled, let interval = tier.interval else { return }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.trackCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func invalidateTimer() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func installEventMonitors() {
        guard globalMouseMonitor == nil && localMouseMonitor == nil else { return }

        // Global monitor observes cursor movements across other apps.
        // Returns nil if accessibility permissions are missing or in sandboxed/headless environments.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleObservedMouseMovement()
            }
        }

        // Local monitor observes cursor movements within AMORA's own windows.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleObservedMouseMovement()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    private func installLifecycleObservers() {
        guard sleepObserver == nil && wakeObserver == nil && screenChangeObserver == nil else { return }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pauseTracking()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resumeTracking()
            }
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
                self.updateScreen(screen)
            }
        }

        if let window {
            windowOcclusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let win = self.window else { return }
                    if win.isVisible && win.occlusionState.contains(.visible) {
                        if self.currentTier == .suspended && self.isTrackingEnabled {
                            self.resumeTracking()
                        }
                    } else if !win.isVisible {
                        if self.currentTier != .suspended {
                            self.setTrackingTier(.suspended)
                        }
                    }
                }
            }
        }
    }

    private func removeLifecycleObservers() {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        if let observer = windowOcclusionObserver {
            NotificationCenter.default.removeObserver(observer)
            windowOcclusionObserver = nil
        }
    }

    private func handleObservedMouseMovement(_ location: CGPoint? = nil) {
        guard isTrackingEnabled else { return }
        let currentPos = location ?? NSEvent.mouseLocation
        let targetScreen = self.screen ?? NotchManager.notchedScreen ?? NSScreen.main
        let notchBounds = targetScreen.map { NotchManager.notchRect(on: $0) } ?? (window?.frame ?? .zero)
        let distance = hypot(currentPos.x - notchBounds.midX, currentPos.y - notchBounds.midY)

        // Accelerate immediately if cursor is approaching or if moving while in idle/distant
        if distance < 250 && currentTier != .active {
            trackCursor(at: currentPos)
        } else if distance < 450 && (currentTier == .idle || currentTier == .distant) {
            trackCursor(at: currentPos)
        } else if currentTier == .idle && currentPos != lastCursorPosition {
            trackCursor(at: currentPos)
        }
    }

    func trackCursor(at position: CGPoint? = nil) {
        guard isTrackingEnabled else {
            if currentTier != .suspended {
                setTrackingTier(.suspended)
            }
            return
        }

        let currentPosition = position ?? NSEvent.mouseLocation
        let targetScreen = self.screen ?? NotchManager.notchedScreen ?? NSScreen.main
        let notchBounds = targetScreen.map { NotchManager.notchRect(on: $0) } ?? (window?.frame ?? .zero)
        let distanceToNotch = hypot(currentPosition.x - notchBounds.midX, currentPosition.y - notchBounds.midY)

        // Check if window is ordered out or minimized
        if let window = self.window, !window.isVisible {
            if distanceToNotch < 200 {
                // User is approaching or hovering near the notch while window was hidden:
                // Restore window and promote tracking to active
                window.orderFrontRegardless()
                setTrackingTier(.active)
            } else {
                // Far from notch while window is hidden:
                // Maintain low-power 1.0s fallback timer (idle tier) so detection stays responsive
                if currentTier != .idle {
                    setTrackingTier(.idle)
                }
                return
            }
        }

        guard let window = self.window, window.isVisible else {
            if currentTier != .idle {
                setTrackingTier(.idle)
            }
            return
        }

        let deltaX = currentPosition.x - lastCursorPosition.x
        let deltaY = currentPosition.y - lastCursorPosition.y
        let isStationary = abs(deltaX) <= 0.1 && abs(deltaY) <= 0.1

        if !isStationary {
            stationaryTicks = 0
            handleCursorMovement(deltaX: deltaX, deltaY: deltaY, currentPosition: currentPosition)
            lastCursorPosition = currentPosition
        } else {
            stationaryTicks += 1
        }

        let windowFrame = window.frame
        let distance = hypot(currentPosition.x - windowFrame.midX, currentPosition.y - windowFrame.midY)
        lastObservedDistance = distance

        // Determine target tracking tier
        let targetTier: CursorTrackingTier
        if IslandModel.shared.isExpanded || IslandModel.shared.targetState != .collapsed {
            targetTier = .active
        } else if distance < 250 {
            targetTier = .active
        } else if distance < 450 {
            targetTier = .approaching
        } else {
            // Distance >= 450 pt
            if isStationary && stationaryTicks >= 2 {
                targetTier = .idle
            } else {
                targetTier = .distant
            }
        }

        if targetTier != currentTier {
            setTrackingTier(targetTier)
        }

        // While the island is expanded or transitioning, keep tracking the cursor for eye
        // movement (above) but don't let proximity drive state transitions —
        // the expanded state is owned by WindowManager / click-outside.
        guard !IslandModel.shared.isExpanded && IslandModel.shared.targetState == .collapsed else { return }

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

    private func handleCursorMovement(deltaX: CGFloat, deltaY: CGFloat, currentPosition: CGPoint) {
        guard let window = self.window else { return }
        let windowFrame = window.frame

        let halfWidth = max(windowFrame.width / 2, 1)
        let halfHeight = max(windowFrame.height / 2, 1)
        let relX = (currentPosition.x - windowFrame.midX) / halfWidth
        let relY = (currentPosition.y - windowFrame.midY) / halfHeight

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
