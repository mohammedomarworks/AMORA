import Cocoa
import Foundation

@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    enum Permission: String, CaseIterable, Sendable {
        case accessibility = "Accessibility"
        case automation = "Automation"
        case calendar = "Calendar"
        case files = "Files"
        case notifications = "Notifications"
        case camera = "Camera"
        case microphone = "Microphone"
    }

    func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let access = AXIsProcessTrustedWithOptions(options)
        return access
    }

    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    func checkAutomation(bundleIdentifier: String = "com.spotify.client") -> Bool {
        SpotifyProvider.checkAutomationPermission()
    }

    func openSystemSettings(for permission: Permission? = nil) {
        if permission == .automation {
            SpotifyProvider.openAutomationSettings()
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") else { return }
        NSWorkspace.shared.open(url)
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return checkAccessibility()
        case .automation:
            return checkAutomation()
        default:
            return false
        }
    }

    func requestIfNeeded(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return requestAccessibility()
        default:
            return false
        }
    }
}
