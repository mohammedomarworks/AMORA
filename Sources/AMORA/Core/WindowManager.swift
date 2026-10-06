import Cocoa
import QuartzCore
import SwiftUI

/// Owns every on-screen surface AMORA presents. The notch experience is a SINGLE
/// window that physically occupies the hardware notch when collapsed and morphs
/// downward into a Dynamic Island when expanded — there is no separate pill or panel.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var islandWindow: NSWindow?
    private var settingsWindow: NSWindow?
    let dashboardViewModel = DashboardViewModel()

    private var notchManager: NotchManager?
    private var clickOutsideMonitor: Any?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var screenConfigurationObserver: Any?

    // Spring-driven morph state (shared across collapsed, quick, and workspace states).
    private var springTimer: Timer?
    private var lastAnimationTimestamp: CFTimeInterval = 0
    private var springPos: Double = 0
    private var springVel: Double = 0
    private var springTarget: Double = 0
    private var collapsedFrameCache: NSRect = .zero
    private var quickFrameCache: NSRect = .zero
    private var workspaceFrameCache: NSRect = .zero
    private var horizontalSwipeAccumulator: CGFloat = 0
    private var horizontalSwipeGestureActive = false
    private var horizontalSwipeHasTriggered = false
    private var monitorStartTime: CFTimeInterval = 0
    private let dismissalManager = OutsideDismissalManager(dragThreshold: 8.0)
    private var dragTrackingTimer: Timer?
    private var initialDragPasteboardChangeCount: Int = 0

    private init() {}

    private enum IslandMetrics {
        /// Minimal downward lip so the collapsed eyes have displayable pixels at the
        /// notch's lower edge. Same width + black as the notch, so it reads as the
        /// notch itself — not a floating pill below it.
        static let collapsedChinHeight: CGFloat = 6
        static let collapsedBottomRadius: CGFloat = 10
        static let quickWidth: CGFloat = 340
        static let quickContentHeight: CGFloat = 452
        static let quickBottomRadius: CGFloat = 30
        static let workspaceBottomRadius: CGFloat = 36
        static let screenMargin: CGFloat = 8
    }

    // MARK: - Geometry

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        let notch = NotchManager.notchRect(on: screen)
        let width = notch.width
        let height = notch.height + IslandMetrics.collapsedChinHeight
        let x = (notch.midX - width / 2).rounded()
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func quickFrame(on screen: NSScreen) -> NSRect {
        let notch = NotchManager.notchRect(on: screen)
        let topInset = notch.height
        let width = IslandMetrics.quickWidth
        let height = topInset + IslandMetrics.quickContentHeight
        var x = (notch.midX - width / 2).rounded()
        let minX = screen.frame.minX + IslandMetrics.screenMargin
        let maxX = screen.frame.maxX - width - IslandMetrics.screenMargin
        if maxX > minX { x = min(max(x, minX), maxX) }
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func workspaceFrame(on screen: NSScreen) -> NSRect {
        let notch = NotchManager.notchRect(on: screen)

        // Responsive sizing:
        // Target width ~800–1000 pt, clamped to screen bounds
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height
        let screenMargin = IslandMetrics.screenMargin

        let maxWidth = screenWidth - (screenMargin * 2)
        let desiredWidth = min(960, max(800, screenWidth * 0.64))
        let width = min(desiredWidth, maxWidth).rounded()

        // Target height ~600–700 pt, clamped to screen bounds (clearing dock/bottom edge)
        let maxHeight = screenHeight - 44
        let desiredHeight = min(680, max(580, screenHeight * 0.70))
        let height = min(desiredHeight, maxHeight).rounded()

        var x = (notch.midX - width / 2).rounded()
        let minX = screen.frame.minX + screenMargin
        let maxX = screen.frame.maxX - width - screenMargin
        if maxX > minX { x = min(max(x, minX), maxX) }
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func configureIslandModel(for screen: NSScreen) {
        let notch = NotchManager.notchRect(on: screen)
        let model = IslandModel.shared
        model.topInset = notch.height
        model.notchWidth = notch.width
        model.collapsedBottomRadius = IslandMetrics.collapsedBottomRadius
        model.quickBottomRadius = IslandMetrics.quickBottomRadius
        model.workspaceBottomRadius = IslandMetrics.workspaceBottomRadius
    }

    // MARK: - Collapsed island (the physical notch itself)

    /// Shows the single island window in its collapsed state: a black, notch-width,
    /// top-pinned surface that merges with the physical notch. No pill, no panel.
    func showNotchWindow() {
        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        configureIslandModel(for: screen)

        if let window = islandWindow {
            if !IslandModel.shared.isExpanded {
                window.setFrame(collapsedFrame(on: screen), display: true)
            }
            window.orderFrontRegardless()
            return
        }

        let frame = collapsedFrame(on: screen)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]

        let host = NSHostingController(rootView: DynamicIslandView())
        host.view.frame = CGRect(origin: .zero, size: frame.size)
        host.view.autoresizingMask = [.width, .height]
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.layer?.isOpaque = false

        window.contentView = host.view

        islandWindow = window
        notchManager = NotchManager(window: window, screen: screen)
        installScreenConfigurationObserver()
        logGeometry(for: screen)
        window.orderFrontRegardless()
    }

    private func logGeometry(for screen: NSScreen) {
        NotchManager.logGeometryIfEnabled(
            for: screen,
            notchRect: NotchManager.notchRect(on: screen),
            amoraFrame: collapsedFrame(on: screen)
        )
        guard UserDefaults.standard.bool(forKey: "AMORADebugGeometry") else { return }
        print("[AMORA] collapsedHitRect=\(collapsedFrame(on: screen))")
        print("[AMORA] quickRect=\(quickFrame(on: screen))")
        print("[AMORA] workspaceRect=\(workspaceFrame(on: screen))")
        if let w = islandWindow { print("[AMORA] windowFrame=\(w.frame)") }
    }

    // MARK: - Expand / collapse (three-state downward morph)

    func toggleQuickPanel() {
        if IslandModel.shared.isExpanded {
            collapseIsland()
        } else {
            expandIsland()
        }
    }

    func showQuickPanel() { expandIsland() }
    func closeQuickPanel() { collapseIsland() }

    var isQuickPanelVisible: Bool { IslandModel.shared.displayState == .quick }
    var isDashboardVisible: Bool { IslandModel.shared.displayState == .workspace }

    /// State 2: Quick Island
    func expandIsland() {
        if islandWindow == nil { showNotchWindow() }
        guard let window = islandWindow,
              let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        configureIslandModel(for: screen)

        IslandModel.shared.targetState = .quick
        AppState.shared.isQuickPanelOpen = true
        AppState.shared.isDashboardOpen = false
        AppState.shared.stateManager.transition(to: .expanded)
        AMORAContext.shared.beginInteraction()
        AMORAEventCenter.shared.emit(.opened)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupClickOutsideMonitor()
        animateIsland(to: 1.0)
    }

    /// State 3: Workspace (enlarged Dynamic Island containing Dashboard functionality)
    func showWorkspace(section: DashboardView.DashboardSection = .overview) {
        dashboardViewModel.selectedSection = section
        if islandWindow == nil { showNotchWindow() }
        guard let window = islandWindow,
              let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        configureIslandModel(for: screen)

        IslandModel.shared.targetState = .workspace
        AppState.shared.isDashboardOpen = true
        AppState.shared.isQuickPanelOpen = false
        AppState.shared.stateManager.transition(to: .expanded)
        AMORAContext.shared.beginInteraction()
        AMORAEventCenter.shared.emit(.opened)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupClickOutsideMonitor()
        animateIsland(to: 2.0)
    }

    /// Contract from Workspace (State 3) back to Quick Island (State 2)
    func contractToQuickIsland() {
        guard islandWindow != nil,
              let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        configureIslandModel(for: screen)

        IslandModel.shared.targetState = .quick
        AppState.shared.isDashboardOpen = false
        AppState.shared.isQuickPanelOpen = true
        animateIsland(to: 1.0)
    }

    /// State 1: Collapsed physical notch
    func collapseIsland() {
        guard islandWindow != nil else {
            AppState.shared.isQuickPanelOpen = false
            AppState.shared.isDashboardOpen = false
            IslandModel.shared.displayState = .collapsed
            IslandModel.shared.targetState = .collapsed
            IslandModel.shared.expansion = 0.0
            return
        }
        IslandModel.shared.targetState = .collapsed
        AppState.shared.isQuickPanelOpen = false
        AppState.shared.isDashboardOpen = false
        AssistantManager.shared.dismissResponse()
        removeClickOutsideMonitor()
        AMORAContext.shared.endInteraction()
        AMORAEventCenter.shared.emit(.closed)
        animateIsland(to: 0.0)
    }

    // MARK: - Spring morph driver

    /// Drives a continuous spring across normalized progress `springPos`:
    ///   0.0 = State 1 (Collapsed Notch)
    ///   1.0 = State 2 (Quick Island)
    ///   2.0 = State 3 (Expanded Workspace)
    ///
    /// Every tick resizes the single host NSWindow and updates `IslandModel.expansion`
    /// to keep AppKit frame morph and SwiftUI content interpolation in exact lockstep.
    private func animateIsland(to target: Double) {
        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        collapsedFrameCache = collapsedFrame(on: screen)
        quickFrameCache = quickFrame(on: screen)
        workspaceFrameCache = workspaceFrame(on: screen)
        springTarget = target
        springTimer?.invalidate()
        lastAnimationTimestamp = CACurrentMediaTime()

        // Physics tuning based on direction and target
        let stiffness: Double
        let damping: Double
        if target <= 0.05 {
            // Collapsing into the physical notch: critically damped so it docks seamlessly into bezel with zero bounce
            stiffness = 310.0
            damping = 35.0
        } else if target >= 1.95 {
            // Expanding into large workspace: fluid, responsive spring
            stiffness = 240.0
            damping = 27.0
        } else if springPos > 1.2 {
            // Contracting from workspace down to quick island: controlled retraction
            stiffness = 270.0
            damping = 31.0
        } else {
            // Expanding from notch to quick island: elastic stretch
            stiffness = 260.0
            damping = 27.5
        }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let window = self.islandWindow else {
                    self.springTimer?.invalidate()
                    self.springTimer = nil
                    return
                }

                let now = CACurrentMediaTime()
                let elapsed = now - self.lastAnimationTimestamp
                self.lastAnimationTimestamp = now
                let dt = min(0.033, max(0.001, elapsed))

                let force = -stiffness * (self.springPos - self.springTarget) - damping * self.springVel
                self.springVel += force * dt
                self.springPos += self.springVel * dt

                // When collapsing into the notch, prevent negative overshoot
                if self.springTarget <= 0.05 && self.springPos < 0.0 {
                    self.springPos = 0.0
                    self.springVel = 0.0
                }

                let dist = abs(self.springPos - self.springTarget)
                let vel = abs(self.springVel)
                if dist < 0.002 && vel < 0.02 {
                    self.springPos = self.springTarget
                    self.springVel = 0
                    self.springTimer?.invalidate()
                    self.springTimer = nil
                    self.finishIslandAnimation()
                    return
                }

                IslandModel.shared.expansion = self.springPos
                window.setFrame(self.interpolatedFrame(self.springPos), display: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }

    private func interpolatedFrame(_ p: Double) -> NSRect {
        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else {
            return quickFrameCache
        }
        let a = collapsedFrameCache
        let b = quickFrameCache
        let c = workspaceFrameCache

        if p <= 1.0 {
            // Interpolating between collapsed (0) and quick (1)
            let f = CGFloat(max(0.0, min(1.05, p)))
            let width = (a.width + (b.width - a.width) * f).rounded()
            let height = (a.height + (b.height - a.height) * f).rounded()
            let x = (a.origin.x + (b.origin.x - a.origin.x) * f).rounded()
            let y = screen.frame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        } else {
            // Interpolating between quick (1) and workspace (2)
            let f = CGFloat(max(0.0, min(1.05, p - 1.0)))
            let width = (b.width + (c.width - b.width) * f).rounded()
            let height = (b.height + (c.height - b.height) * f).rounded()
            let x = (b.origin.x + (c.origin.x - b.origin.x) * f).rounded()
            let y = screen.frame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }

    private func finishIslandAnimation() {
        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        if springTarget >= 1.5 {
            IslandModel.shared.displayState = .workspace
            IslandModel.shared.targetState = .workspace
            IslandModel.shared.expansion = 2.0
            AppState.shared.isDashboardOpen = true
            AppState.shared.isQuickPanelOpen = false
            islandWindow?.setFrame(workspaceFrame(on: screen), display: true)
        } else if springTarget >= 0.5 {
            IslandModel.shared.displayState = .quick
            IslandModel.shared.targetState = .quick
            IslandModel.shared.expansion = 1.0
            AppState.shared.isDashboardOpen = false
            AppState.shared.isQuickPanelOpen = true
            islandWindow?.setFrame(quickFrame(on: screen), display: true)
        } else {
            IslandModel.shared.displayState = .collapsed
            IslandModel.shared.targetState = .collapsed
            IslandModel.shared.expansion = 0.0
            AppState.shared.isDashboardOpen = false
            AppState.shared.isQuickPanelOpen = false
            islandWindow?.setFrame(collapsedFrame(on: screen), display: true)
        }
    }

    // MARK: - Click-outside + Keyboard / Scroll Monitors

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()
        monitorStartTime = CACurrentMediaTime()
        dismissalManager.reset()

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown
        ]

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = self.islandWindow, IslandModel.shared.isExpanded else { return }
                guard CACurrentMediaTime() - self.monitorStartTime > 0.3 else { return }

                let point = NSEvent.mouseLocation
                let isInside = window.frame.contains(point)
                let now = CACurrentMediaTime()

                switch event.type {
                case .leftMouseDown:
                    let action = self.dismissalManager.handleMouseDown(at: point, isInsideWindow: isInside, timestamp: now)
                    if action == .dismiss {
                        self.stopDragTrackingTimer()
                        self.collapseIsland()
                    } else if self.dismissalManager.isPendingOutsideClick {
                        self.startDragTrackingTimer(from: point)
                    }

                case .leftMouseDragged:
                    let action = self.dismissalManager.handleMouseDragged(to: point, isInsideWindow: isInside, timestamp: now)
                    if self.dismissalManager.isExternalDragInProgress {
                        self.stopDragTrackingTimer()
                    }
                    if action == .dismiss {
                        self.stopDragTrackingTimer()
                        self.collapseIsland()
                    }

                case .leftMouseUp:
                    self.stopDragTrackingTimer()
                    let action = self.dismissalManager.handleMouseUp(at: point, isInsideWindow: isInside, timestamp: now)
                    if action == .dismiss {
                        self.collapseIsland()
                    }

                case .rightMouseDown:
                    self.stopDragTrackingTimer()
                    if !isInside && !self.dismissalManager.isExternalDragInProgress {
                        self.dismissalManager.reset()
                        self.collapseIsland()
                    }

                default:
                    break
                }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Arrow keys only paginate in Quick Island mode (never hijack in Workspace mode)
            if event.keyCode == 123 || event.keyCode == 124 {
                if IslandModel.shared.displayState == .quick {
                    MainActor.assumeIsolated {
                        let direction: AMORAPageSwipe = event.keyCode == 124 ? .next : .previous
                        NotificationCenter.default.post(
                            name: .amoraPageKeyboard,
                            object: nil,
                            userInfo: [AMORAPageSwipe.directionKey: direction]
                        )
                    }
                    return nil
                }
                return event
            }
            guard event.keyCode == 53 else { return event } // ESC
            MainActor.assumeIsolated {
                guard let self else { return }
                if IslandModel.shared.displayState == .workspace {
                    self.contractToQuickIsland()
                } else if IslandModel.shared.isExpanded {
                    self.collapseIsland()
                }
            }
            return nil
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self,
                  IslandModel.shared.displayState == .quick,
                  let window = self.islandWindow,
                  window.frame.contains(NSEvent.mouseLocation),
                  event.hasPreciseScrollingDeltas else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy), abs(dx) > 0.01 else { return event }

            MainActor.assumeIsolated {
                self.handleIslandHorizontalScroll(event)
            }
            // Consume only horizontal, precise events over the quick island.
            return nil
        }
    }

    private func startDragTrackingTimer(from startPoint: CGPoint) {
        stopDragTrackingTimer()
        initialDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.dismissalManager.isPendingOutsideClick else {
                    self.stopDragTrackingTimer()
                    return
                }

                let currentPoint = NSEvent.mouseLocation
                let movedState = self.dismissalManager.checkMovement(at: currentPoint)
                let currentDragPbCount = NSPasteboard(name: .drag).changeCount

                if case .externalDrag = movedState {
                    self.stopDragTrackingTimer()
                } else if currentDragPbCount != self.initialDragPasteboardChangeCount {
                    self.dismissalManager.handleMouseDragged(to: currentPoint, isInsideWindow: false)
                    self.stopDragTrackingTimer()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTrackingTimer = timer
    }

    private func stopDragTrackingTimer() {
        dragTrackingTimer?.invalidate()
        dragTrackingTimer = nil
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        stopDragTrackingTimer()
        dismissalManager.reset()
        horizontalSwipeAccumulator = 0
        horizontalSwipeGestureActive = false
        horizontalSwipeHasTriggered = false
    }

    private func handleIslandHorizontalScroll(_ event: NSEvent) {
        let phaseBegan = event.phase.contains(.began)
        let phaseEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        let momentumBegan = event.momentumPhase.contains(.began)
        let momentumEnded = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)

        if phaseBegan {
            horizontalSwipeAccumulator = 0
            horizontalSwipeGestureActive = true
            horizontalSwipeHasTriggered = false
        }

        if momentumBegan {
            horizontalSwipeGestureActive = true
        }

        guard !horizontalSwipeHasTriggered else {
            if momentumEnded || (phaseEnded && event.momentumPhase.isEmpty) {
                finishHorizontalSwipeGesture()
            }
            return
        }

        if phaseEnded && (event.momentumPhase.isEmpty || momentumEnded) {
            finishHorizontalSwipeGesture()
            return
        }

        let translationX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        horizontalSwipeAccumulator += translationX

        let threshold: CGFloat = 36
        guard abs(horizontalSwipeAccumulator) >= threshold else {
            return
        }

        let direction: AMORAPageSwipe = horizontalSwipeAccumulator < 0 ? .next : .previous
        NotificationCenter.default.post(
            name: .amoraPageSwipe,
            object: nil,
            userInfo: [AMORAPageSwipe.directionKey: direction]
        )
        horizontalSwipeAccumulator = 0
        horizontalSwipeHasTriggered = true
    }

    private func finishHorizontalSwipeGesture() {
        guard horizontalSwipeGestureActive else { return }
        horizontalSwipeAccumulator = 0
        horizontalSwipeGestureActive = false
        horizontalSwipeHasTriggered = false
    }

    // MARK: - Screen configuration + pause/restore

    private func installScreenConfigurationObserver() {
        guard screenConfigurationObserver == nil else { return }
        screenConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      let screen = NotchManager.notchedScreen ?? NSScreen.main,
                      let window = self.islandWindow else { return }
                self.configureIslandModel(for: screen)
                let target: NSRect
                switch IslandModel.shared.displayState {
                case .workspace: target = self.workspaceFrame(on: screen)
                case .quick: target = self.quickFrame(on: screen)
                case .collapsed: target = self.collapsedFrame(on: screen)
                }
                window.setFrame(target, display: true)
                self.logGeometry(for: screen)
            }
        }
    }

    func minimizeAll() {
        islandWindow?.orderOut(nil)
    }

    func restoreAll() {
        if !IslandModel.shared.isExpanded {
            islandWindow?.orderFrontRegardless()
        } else {
            islandWindow?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Dashboard / Workspace Bridge + Settings

    /// Preserves existing callers (menu bar, command system, AI tools) by opening the Workspace state.
    func showDashboard(section: DashboardView.DashboardSection = .overview) {
        showWorkspace(section: section)
    }

    func closeDashboard() {
        contractToQuickIsland()
    }

    func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AMORA Settings"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingController(rootView: SettingsView()).view

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
