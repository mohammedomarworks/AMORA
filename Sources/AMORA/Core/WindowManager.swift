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
    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var notchManager: NotchManager?
    private var clickOutsideMonitor: Any?
    private var keyMonitor: Any?
    private var screenConfigurationObserver: Any?

    // Spring-driven morph state (shared by expand + collapse so interruptions are smooth).
    private var springTimer: Timer?
    private var springPos: Double = 0
    private var springVel: Double = 0
    private var springTarget: Double = 0
    private var collapsedFrameCache: NSRect = .zero
    private var expandedFrameCache: NSRect = .zero

    private init() {}

    private enum IslandMetrics {
        /// Minimal downward lip so the collapsed eyes have displayable pixels at the
        /// notch's lower edge. Same width + black as the notch, so it reads as the
        /// notch itself — not a floating pill below it.
        static let collapsedChinHeight: CGFloat = 6
        static let collapsedBottomRadius: CGFloat = 10
        static let expandedWidth: CGFloat = 340
        static let expandedContentHeight: CGFloat = 452
        static let expandedBottomRadius: CGFloat = 30
        static let screenMargin: CGFloat = 8
    }

    // MARK: - Geometry

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        let notch = NotchManager.notchRect(on: screen)
        let width = notch.width
        let height = notch.height + IslandMetrics.collapsedChinHeight
        let x = notch.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let notch = NotchManager.notchRect(on: screen)
        let topInset = notch.height
        let width = IslandMetrics.expandedWidth
        let height = topInset + IslandMetrics.expandedContentHeight
        var x = notch.midX - width / 2
        let minX = screen.frame.minX + IslandMetrics.screenMargin
        let maxX = screen.frame.maxX - width - IslandMetrics.screenMargin
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
        model.expandedBottomRadius = IslandMetrics.expandedBottomRadius
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
        print("[AMORA] expandedRect=\(expandedFrame(on: screen))")
        if let w = islandWindow { print("[AMORA] windowFrame=\(w.frame)") }
    }

    // MARK: - Expand / collapse (the downward morph)

    func toggleQuickPanel() {
        if IslandModel.shared.isExpanded { collapseIsland() } else { expandIsland() }
    }

    func showQuickPanel() { expandIsland() }
    func closeQuickPanel() { collapseIsland() }

    var isQuickPanelVisible: Bool { IslandModel.shared.isExpanded }

    func expandIsland() {
        if islandWindow == nil { showNotchWindow() }
        guard let window = islandWindow,
              let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        configureIslandModel(for: screen)

        IslandModel.shared.isExpanded = true
        AppState.shared.isQuickPanelOpen = true
        AppState.shared.stateManager.transition(to: .expanded)
        AMORAContext.shared.beginInteraction()
        AMORAEventCenter.shared.emit(.opened)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupClickOutsideMonitor()
        animateIsland(to: 1)
    }

    func collapseIsland() {
        guard islandWindow != nil else {
            AppState.shared.isQuickPanelOpen = false
            IslandModel.shared.isExpanded = false
            return
        }
        IslandModel.shared.isExpanded = false
        AppState.shared.isQuickPanelOpen = false
        AssistantManager.shared.dismissResponse()
        removeClickOutsideMonitor()
        AMORAContext.shared.endInteraction()
        AMORAEventCenter.shared.emit(.closed)
        animateIsland(to: 0)
    }

    // MARK: - Spring morph driver

    /// Drives a single spring on a normalized progress `springPos` (0 = collapsed,
    /// 1 = expanded). Each tick resizes the window frame AND publishes the progress
    /// to `IslandModel`, so the AppKit frame morph and the SwiftUI content stay in
    /// perfect sync. Keeping `springPos`/`springVel` across calls makes a reversal
    /// mid-animation (expand → click-outside) continue smoothly from where it is.
    private func animateIsland(to target: Double) {
        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        collapsedFrameCache = collapsedFrame(on: screen)
        expandedFrameCache = expandedFrame(on: screen)
        springTarget = target
        springTimer?.invalidate()

        let dt = 1.0 / 120.0
        let stiffness = 240.0
        let damping = 26.0

        springTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let window = self.islandWindow else {
                    self.springTimer?.invalidate()
                    self.springTimer = nil
                    return
                }
                let force = -stiffness * (self.springPos - self.springTarget) - damping * self.springVel
                self.springVel += force * dt
                self.springPos += self.springVel * dt

                if abs(self.springPos - self.springTarget) < 0.001 && abs(self.springVel) < 0.01 {
                    self.springPos = self.springTarget
                    self.springVel = 0
                    self.springTimer?.invalidate()
                    self.springTimer = nil
                    self.finishIslandAnimation()
                    return
                }

                IslandModel.shared.expansion = self.springPos
                window.setFrame(self.interpolatedFrame(self.springPos), display: true)
            }
        }
    }

    private func interpolatedFrame(_ p: Double) -> NSRect {
        let f = CGFloat(max(0, min(1.1, p)))
        let a = collapsedFrameCache
        let b = expandedFrameCache
        return NSRect(
            x: a.origin.x + (b.origin.x - a.origin.x) * f,
            y: a.origin.y + (b.origin.y - a.origin.y) * f,
            width: a.width + (b.width - a.width) * f,
            height: a.height + (b.height - a.height) * f
        )
    }

    private func finishIslandAnimation() {
        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        if springTarget >= 0.5 {
            IslandModel.shared.expansion = 1
            islandWindow?.setFrame(expandedFrame(on: screen), display: true)
        } else {
            IslandModel.shared.expansion = 0
            islandWindow?.setFrame(collapsedFrame(on: screen), display: true)
        }
    }

    // MARK: - Click-outside + ESC to collapse

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.islandWindow, IslandModel.shared.isExpanded else { return }
                if !window.frame.contains(NSEvent.mouseLocation) {
                    self.collapseIsland()
                }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event } // ESC
            MainActor.assumeIsolated {
                if IslandModel.shared.isExpanded { self?.collapseIsland() }
            }
            return nil
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
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
                let target = IslandModel.shared.isExpanded ? self.expandedFrame(on: screen) : self.collapsedFrame(on: screen)
                window.setFrame(target, display: true)
                self.logGeometry(for: screen)
            }
        }
    }

    func minimizeAll() {
        islandWindow?.orderOut(nil)
        dashboardWindow?.orderOut(nil)
    }

    func restoreAll() {
        if !IslandModel.shared.isExpanded {
            islandWindow?.orderFrontRegardless()
        }
    }

    // MARK: - Dashboard (full presence level) + Settings

    func showDashboard(section: DashboardView.DashboardSection = .overview) {
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            AppState.shared.isDashboardOpen = true
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AMORA"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingController(rootView: DashboardView(initialSection: section)).view

        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppState.shared.isDashboardOpen = true
    }

    func closeDashboard() {
        dashboardWindow?.orderOut(nil)
        AppState.shared.isDashboardOpen = false
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
