import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowManager: WindowManager?
    private var permissionManager: PermissionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory agent application so it lives seamlessly in menu bar / notch without dock clutter
        NSApp.setActivationPolicy(.accessory)

        AppState.shared.handleLaunch()

        windowManager = WindowManager.shared
        permissionManager = PermissionManager.shared

        setupMenuBar()
        windowManager?.showNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.handleTerminate()
    }

    func applicationWillResignActive(_ notification: Notification) {
        // Keep active or minimize if needed
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        windowManager?.restoreAll()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "AMORA")
            button.toolTip = "AMORA - Your Little Mac Companion"
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Show AMORA", action: #selector(openAMORA), keyEquivalent: "o")
        menu.addItem(openItem)

        let quickPanelItem = NSMenuItem(title: "Quick Controls", action: #selector(toggleQuickPanel), keyEquivalent: "p")
        menu.addItem(quickPanelItem)

        let dashboardItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause AMORA", action: #selector(pauseAMORA), keyEquivalent: "")
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About AMORA", action: #selector(openAbout), keyEquivalent: "")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit AMORA", action: #selector(quitAMORA), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openAMORA() {
        windowManager?.showNotchWindow()
    }

    @objc private func toggleQuickPanel() {
        windowManager?.toggleQuickPanel()
    }

    @objc private func openDashboard() {
        windowManager?.showDashboard()
    }

    @objc private func pauseAMORA() {
        AppState.shared.isPaused.toggle()
        if AppState.shared.isPaused {
            windowManager?.minimizeAll()
        } else {
            windowManager?.restoreAll()
        }
    }

    @objc private func openSettings() {
        windowManager?.showSettings()
    }

    @objc private func openAbout() {
        let alert = NSAlert()
        alert.messageText = "AMORA"
        alert.informativeText = "Your little Mac companion.\nLiving right around your MacBook notch.\nVersion 1.0.0"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitAMORA() {
        NSApp.terminate(nil)
    }
}
