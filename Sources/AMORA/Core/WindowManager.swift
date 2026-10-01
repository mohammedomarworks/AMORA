import Cocoa
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var notchWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var quickPanelWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var notchManager: NotchManager?
    private var clickOutsideMonitor: Any?

    private init() {}

    // MARK: - Notch Window

    func showNotchWindow() {
        if let existing = notchWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        guard let screen = NotchManager.notchedScreen ?? NSScreen.main else { return }
        let notchFrame = NotchManager.notchRect(on: screen)

        // Make window slightly wider/taller than the physical notch to host the robot nicely
        let windowWidth: CGFloat = max(notchFrame.width, 210)
        let windowHeight: CGFloat = max(notchFrame.height + 4, 38)
        let windowOriginX = screen.frame.midX - (windowWidth / 2)
        let windowOriginY = screen.frame.maxY - windowHeight

        let windowRect = NSRect(x: windowOriginX, y: windowOriginY, width: windowWidth, height: windowHeight)

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        window.hasShadow = false

        let hostingController = NSHostingController(rootView: NotchView())
        window.contentView = hostingController.view

        self.notchManager = NotchManager(window: window, screen: screen)
        self.notchWindow = window
        window.orderFrontRegardless()
    }

    func minimizeAll() {
        notchWindow?.orderOut(nil)
        quickPanelWindow?.orderOut(nil)
        dashboardWindow?.orderOut(nil)
    }

    func restoreAll() {
        notchWindow?.orderFrontRegardless()
    }

    // MARK: - Quick Panel

    func toggleQuickPanel() {
        if let panel = quickPanelWindow, panel.isVisible {
            closeQuickPanel()
        } else {
            showQuickPanel()
        }
    }

    func showQuickPanel() {
        guard let screen = notchWindow?.screen ?? NSScreen.main else { return }
        let panelSize = NSSize(width: 320, height: 420)

        let notchY = notchWindow?.frame.minY ?? (screen.frame.maxY - 40)
        let panelOrigin = CGPoint(
            x: screen.frame.midX - (panelSize.width / 2),
            y: notchY - panelSize.height - 8
        )

        let window: NSWindow
        if let existing = quickPanelWindow {
            window = existing
            window.setFrame(NSRect(origin: panelOrigin, size: panelSize), display: true)
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: panelOrigin, size: panelSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let hostingController = NSHostingController(rootView: QuickPanelView())
            window.contentView = hostingController.view
            self.quickPanelWindow = window
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupClickOutsideMonitor()
    }

    func closeQuickPanel() {
        quickPanelWindow?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self, let panel = self.quickPanelWindow, panel.isVisible else { return }
                let mouseLocation = NSEvent.mouseLocation
                if !panel.frame.contains(mouseLocation) && !(self.notchWindow?.frame.contains(mouseLocation) ?? false) {
                    self.closeQuickPanel()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Dashboard

    func showDashboard() {
        closeQuickPanel()

        if let existing = dashboardWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let screen = notchWindow?.screen ?? NSScreen.main else { return }
        let dashboardSize = NSSize(width: 480, height: 600)
        let dashboardOrigin = CGPoint(
            x: screen.frame.midX - (dashboardSize.width / 2),
            y: screen.frame.midY - (dashboardSize.height / 2)
        )

        let window = NSWindow(
            contentRect: NSRect(origin: dashboardOrigin, size: dashboardSize),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let hostingController = NSHostingController(rootView: DashboardView())
        window.contentView = hostingController.view

        self.dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeDashboard() {
        dashboardWindow?.orderOut(nil)
    }

    // MARK: - Settings

    func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
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
        window.center()
        window.isReleasedWhenClosed = false

        let hostingController = NSHostingController(rootView: SettingsView())
        window.contentView = hostingController.view

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
