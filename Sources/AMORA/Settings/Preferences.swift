import Foundation
import SwiftUI
import Observation

@Observable @MainActor
final class SettingsStore {
    // Appearance
    var theme: Theme = .midnight
    var accentColor: String = "blue"
    var amoraSize: CGFloat = 32
    var transparency: Double = 0.85
    var animationIntensity: Double = 1.0

    // Behavior
    var launchAtLogin: Bool = true
    var alwaysShowAMORA: Bool = true
    var hoverToExpand: Bool = true
    var clickToExpand: Bool = true
    var autoCollapseDelay: Double = 3.0
    var sleepMode: Bool = true
    var idleTimeout: Double = 300.0

    // Modules
    var musicEnabled: Bool = true
    var volumeEnabled: Bool = true
    var brightnessEnabled: Bool = true
    var batteryEnabled: Bool = true
    var clipboardEnabled: Bool = true
    var fileShelfEnabled: Bool = true
    var timerEnabled: Bool = true
    var notesEnabled: Bool = true
    var calendarEnabled: Bool = true
    var notificationsEnabled: Bool = false
    var systemMonitorEnabled: Bool = true
    var aiEnabled: Bool = false

    // AI
    var aiProvider: String = "anthropic"
    var aiModel: String = "claude-3-5-sonnet-20241022"
    var aiApiKey: String = ""

    // Privacy
    var collectAnalytics: Bool = false

    // Sound
    var soundEnabled: Bool = true
    var soundVolume: Double = 0.5

    // First run
    var hasCompletedFirstRun: Bool = false

    // Global shortcut
    var globalShortcut: String = "Cmd+Shift+Space"

    func load() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "AMORA_hoverToExpand") != nil {
            self.hoverToExpand = defaults.bool(forKey: "AMORA_hoverToExpand")
        }
        if defaults.object(forKey: "AMORA_clickToExpand") != nil {
            self.clickToExpand = defaults.bool(forKey: "AMORA_clickToExpand")
        }
        if let themeStr = defaults.string(forKey: "AMORA_theme"), let th = Theme(rawValue: themeStr) {
            self.theme = th
        }
        if let key = defaults.string(forKey: "AMORA_aiApiKey") {
            self.aiApiKey = key
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(hoverToExpand, forKey: "AMORA_hoverToExpand")
        defaults.set(clickToExpand, forKey: "AMORA_clickToExpand")
        defaults.set(theme.rawValue, forKey: "AMORA_theme")
        defaults.set(aiApiKey, forKey: "AMORA_aiApiKey")
    }
}

enum Theme: String, CaseIterable, Codable, Sendable {
    case midnight = "Midnight"
    case ocean = "Ocean"
    case bubblegum = "Bubblegum"
    case matrix = "Matrix"
    case minimal = "Minimal"
}
