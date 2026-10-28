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
    var clipboardEnabled: Bool = true {
        didSet {
            guard !isLoadingSettings else { return }
            if !clipboardEnabled {
                ClipboardService.shared.clearHistory()
                ClipboardService.shared.stopPolling()
            } else {
                ClipboardService.shared.startPolling()
            }
        }
    }
    var fileShelfEnabled: Bool = true
    var timerEnabled: Bool = true
    var notesEnabled: Bool = true
    var calendarEnabled: Bool = true
    var notificationsEnabled: Bool = false
    var systemMonitorEnabled: Bool = true
    var aiEnabled: Bool = true
    var contextAwarenessEnabled: Bool = true
    var memoryEnabled: Bool = true
    var voiceCommandsEnabled: Bool = true
    var preferOnDeviceRecognition: Bool = true
    var wakeWordEnabled: Bool = false {
        didSet {
            guard !isLoadingSettings else { return }
            if wakeWordEnabled {
                WakeWordService.shared.startIfEnabled()
            } else {
                WakeWordService.shared.stop()
            }
        }
    }
    var wakeWordEngineKind: String = WakeWordEngineKind.nativeAcoustic.rawValue {
        didSet {
            guard !isLoadingSettings else { return }
            updateWakeWordEngine()
        }
    }
    var wakeWordSensitivity: Double = 0.7
    var porcupineAccessKey: String = "" {
        didSet {
            guard !isLoadingSettings else { return }
            if wakeWordEngineKind == WakeWordEngineKind.porcupine.rawValue {
                updateWakeWordEngine()
            }
        }
    }
    var porcupineKeywordPath: String = "" {
        didSet {
            guard !isLoadingSettings else { return }
            if wakeWordEngineKind == WakeWordEngineKind.porcupine.rawValue {
                updateWakeWordEngine()
            }
        }
    }

    func updateWakeWordEngine() {
        if wakeWordEngineKind == WakeWordEngineKind.porcupine.rawValue {
            let porcupine = PorcupineWakeWordEngine(
                accessKey: porcupineAccessKey,
                keywordPath: porcupineKeywordPath.isEmpty ? nil : porcupineKeywordPath
            )
            WakeWordService.shared.configure(engine: porcupine)
        } else {
            WakeWordService.shared.configure(engine: NativeAcousticWakeWordEngine())
        }
    }

    // Storage loading flag
    private var isLoadingSettings: Bool = false

    // Proactive AMORA
    var proactiveAmoraEnabled: Bool = true {
        didSet {
            guard !isLoadingSettings else { return }
            if !proactiveAmoraEnabled {
                AmoraProactiveService.shared.dismissCurrentSuggestion()
            }
        }
    }
    var proactiveTimerCompletedEnabled: Bool = true
    var proactiveTimerNearlyFinishedEnabled: Bool = true
    var proactiveMusicPlaybackEnabled: Bool = true
    var proactiveInactivityReturnEnabled: Bool = true
    var proactiveBatteryCriticalEnabled: Bool = true

    var proactiveSettingsSnapshot: AmoraProactiveSettings {
        AmoraProactiveSettings(
            isEnabled: proactiveAmoraEnabled,
            timerCompletedEnabled: proactiveTimerCompletedEnabled,
            timerNearlyFinishedEnabled: proactiveTimerNearlyFinishedEnabled,
            musicPlaybackEnabled: proactiveMusicPlaybackEnabled,
            inactivityReturnEnabled: proactiveInactivityReturnEnabled,
            batteryCriticalEnabled: proactiveBatteryCriticalEnabled
        )
    }

    // AI
    var aiProvider: String = defaultAIProvider()
    var aiModel: String = defaultAIModel(for: defaultAIProvider())
    var aiApiKey: String = ""

    static func defaultAIProvider(appleChecker: any AppleOnDeviceAvailabilityChecking = AppleOnDeviceAvailability.current) -> String {
        if appleChecker.isSupported() {
            return AIProviderKind.appleOnDevice.rawValue
        } else {
            return AIProviderKind.local.rawValue
        }
    }

    static func defaultAIModel(for provider: String) -> String {
        if provider == AIProviderKind.appleOnDevice.rawValue {
            return "apple-on-device"
        } else if provider == AIProviderKind.local.rawValue {
            return AmoraModelDescriptor.defaultModel.id
        }
        return "default"
    }

    var aiSettingsSnapshot: AISettingsSnapshot {
        AISettingsSnapshot(enabled: aiEnabled,
                           provider: AIProviderKind(rawValue: aiProvider) ?? .appleOnDevice,
                           model: aiModel,
                           apiKey: aiApiKey.isEmpty ? nil : aiApiKey,
                           contextAwarenessEnabled: contextAwarenessEnabled,
                           memoryEnabled: memoryEnabled)
    }

    // Privacy
    var collectAnalytics: Bool = false

    // Sound
    var soundEnabled: Bool = true
    var soundVolume: Double = 0.5

    // First run
    var hasCompletedFirstRun: Bool = false

    // Global shortcut
    var globalShortcut: String = "Cmd+Shift+Space"

    /// Single multiplier for non-essential motion: 0 under the system's Reduce
    /// Motion setting, otherwise the user's animation-intensity slider. Views and
    /// the character read this so motion respects accessibility in one place.
    var motionScale: Double {
        MotionConfig.reduceMotion ? 0.0 : max(0.0, min(1.0, animationIntensity))
    }

    /// Centralized colors for the active theme — the single source of brand color.
    var palette: ThemePalette { theme.palette }

    func load(defaults: UserDefaults = .standard) {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        if defaults.object(forKey: "AMORA_hasCompletedFirstRun") != nil {
            self.hasCompletedFirstRun = defaults.bool(forKey: "AMORA_hasCompletedFirstRun")
        }
        if defaults.object(forKey: "AMORA_hoverToExpand") != nil {
            self.hoverToExpand = defaults.bool(forKey: "AMORA_hoverToExpand")
        }
        if defaults.object(forKey: "AMORA_clickToExpand") != nil {
            self.clickToExpand = defaults.bool(forKey: "AMORA_clickToExpand")
        }
        if defaults.object(forKey: "AMORA_sleepMode") != nil {
            self.sleepMode = defaults.bool(forKey: "AMORA_sleepMode")
        }
        if defaults.object(forKey: "AMORA_soundEnabled") != nil {
            self.soundEnabled = defaults.bool(forKey: "AMORA_soundEnabled")
        }
        if defaults.object(forKey: "AMORA_soundVolume") != nil {
            self.soundVolume = defaults.double(forKey: "AMORA_soundVolume")
        }
        if defaults.object(forKey: "AMORA_aiEnabled") != nil { self.aiEnabled = defaults.bool(forKey: "AMORA_aiEnabled") }
        if defaults.object(forKey: "AMORA_contextAwarenessEnabled") != nil {
            self.contextAwarenessEnabled = defaults.bool(forKey: "AMORA_contextAwarenessEnabled")
        }
        if defaults.object(forKey: "AMORA_memoryEnabled") != nil {
            self.memoryEnabled = defaults.bool(forKey: "AMORA_memoryEnabled")
        }
        if defaults.object(forKey: "AMORA_voiceCommandsEnabled") != nil {
            self.voiceCommandsEnabled = defaults.bool(forKey: "AMORA_voiceCommandsEnabled")
        }
        if defaults.object(forKey: "AMORA_preferOnDeviceRecognition") != nil {
            self.preferOnDeviceRecognition = defaults.bool(forKey: "AMORA_preferOnDeviceRecognition")
        }
        if defaults.object(forKey: "AMORA_wakeWordEnabled") != nil {
            self.wakeWordEnabled = defaults.bool(forKey: "AMORA_wakeWordEnabled")
        }
        if let kind = defaults.string(forKey: "AMORA_wakeWordEngineKind") {
            self.wakeWordEngineKind = kind
        }
        if defaults.object(forKey: "AMORA_wakeWordSensitivity") != nil {
            self.wakeWordSensitivity = defaults.double(forKey: "AMORA_wakeWordSensitivity")
        }
        if let keywordPath = defaults.string(forKey: "AMORA_porcupineKeywordPath") {
            self.porcupineKeywordPath = keywordPath
        }
        self.porcupineAccessKey = StorageManager.shared.getSecureItem(forKey: "porcupine-access-key") ?? ""
        updateWakeWordEngine()
        if defaults.object(forKey: "AMORA_proactiveAmoraEnabled") != nil {
            self.proactiveAmoraEnabled = defaults.bool(forKey: "AMORA_proactiveAmoraEnabled")
        }
        if defaults.object(forKey: "AMORA_proactiveTimerCompletedEnabled") != nil {
            self.proactiveTimerCompletedEnabled = defaults.bool(forKey: "AMORA_proactiveTimerCompletedEnabled")
        }
        if defaults.object(forKey: "AMORA_proactiveTimerNearlyFinishedEnabled") != nil {
            self.proactiveTimerNearlyFinishedEnabled = defaults.bool(forKey: "AMORA_proactiveTimerNearlyFinishedEnabled")
        }
        if defaults.object(forKey: "AMORA_proactiveMusicPlaybackEnabled") != nil {
            self.proactiveMusicPlaybackEnabled = defaults.bool(forKey: "AMORA_proactiveMusicPlaybackEnabled")
        }
        if defaults.object(forKey: "AMORA_proactiveInactivityReturnEnabled") != nil {
            self.proactiveInactivityReturnEnabled = defaults.bool(forKey: "AMORA_proactiveInactivityReturnEnabled")
        }
        if defaults.object(forKey: "AMORA_proactiveBatteryCriticalEnabled") != nil {
            self.proactiveBatteryCriticalEnabled = defaults.bool(forKey: "AMORA_proactiveBatteryCriticalEnabled")
        }
        if defaults.object(forKey: "AMORA_animationIntensity") != nil {
            self.animationIntensity = defaults.double(forKey: "AMORA_animationIntensity")
        }
        if defaults.object(forKey: "AMORA_amoraSize") != nil {
            self.amoraSize = defaults.double(forKey: "AMORA_amoraSize")
        }
        if defaults.object(forKey: "AMORA_autoCollapseDelay") != nil {
            self.autoCollapseDelay = defaults.double(forKey: "AMORA_autoCollapseDelay")
        }
        if defaults.object(forKey: "AMORA_transparency") != nil {
            self.transparency = defaults.double(forKey: "AMORA_transparency")
        }
        if defaults.object(forKey: "AMORA_batteryEnabled") != nil {
            self.batteryEnabled = defaults.bool(forKey: "AMORA_batteryEnabled")
        }
        if defaults.object(forKey: "AMORA_timerEnabled") != nil {
            self.timerEnabled = defaults.bool(forKey: "AMORA_timerEnabled")
        }
        if defaults.object(forKey: "AMORA_musicEnabled") != nil {
            self.musicEnabled = defaults.bool(forKey: "AMORA_musicEnabled")
        }
        if defaults.object(forKey: "AMORA_clipboardEnabled") != nil {
            self.clipboardEnabled = defaults.bool(forKey: "AMORA_clipboardEnabled")
        }
        if defaults.object(forKey: "AMORA_notesEnabled") != nil {
            self.notesEnabled = defaults.bool(forKey: "AMORA_notesEnabled")
        }
        if defaults.object(forKey: "AMORA_systemMonitorEnabled") != nil {
            self.systemMonitorEnabled = defaults.bool(forKey: "AMORA_systemMonitorEnabled")
        }
        if let themeStr = defaults.string(forKey: "AMORA_theme"), let th = Theme(rawValue: themeStr) {
            self.theme = th
        }
        self.aiApiKey = StorageManager.shared.getSecureItem(forKey: "ai-api-key") ?? ""
        if let provider = defaults.string(forKey: "AMORA_aiProvider") {
            self.aiProvider = provider
        } else {
            self.aiProvider = Self.defaultAIProvider()
            if self.aiProvider == AIProviderKind.local.rawValue {
                self.aiModel = Self.defaultAIModel(for: self.aiProvider)
            }
        }
        if let model = defaults.string(forKey: "AMORA_aiModel") { self.aiModel = model }
        defaults.removeObject(forKey: "AMORA_aiApiKey")
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(hasCompletedFirstRun, forKey: "AMORA_hasCompletedFirstRun")
        defaults.set(hoverToExpand, forKey: "AMORA_hoverToExpand")
        defaults.set(clickToExpand, forKey: "AMORA_clickToExpand")
        defaults.set(sleepMode, forKey: "AMORA_sleepMode")
        defaults.set(soundEnabled, forKey: "AMORA_soundEnabled")
        defaults.set(soundVolume, forKey: "AMORA_soundVolume")
        defaults.set(animationIntensity, forKey: "AMORA_animationIntensity")
        defaults.set(amoraSize, forKey: "AMORA_amoraSize")
        defaults.set(transparency, forKey: "AMORA_transparency")
        defaults.set(batteryEnabled, forKey: "AMORA_batteryEnabled")
        defaults.set(timerEnabled, forKey: "AMORA_timerEnabled")
        defaults.set(musicEnabled, forKey: "AMORA_musicEnabled")
        defaults.set(clipboardEnabled, forKey: "AMORA_clipboardEnabled")
        defaults.set(notesEnabled, forKey: "AMORA_notesEnabled")
        defaults.set(systemMonitorEnabled, forKey: "AMORA_systemMonitorEnabled")
        defaults.set(autoCollapseDelay, forKey: "AMORA_autoCollapseDelay")
        defaults.set(theme.rawValue, forKey: "AMORA_theme")
        defaults.set(aiProvider, forKey: "AMORA_aiProvider")
        defaults.set(aiModel, forKey: "AMORA_aiModel")
        defaults.set(aiEnabled, forKey: "AMORA_aiEnabled")
        defaults.set(contextAwarenessEnabled, forKey: "AMORA_contextAwarenessEnabled")
        defaults.set(memoryEnabled, forKey: "AMORA_memoryEnabled")
        defaults.set(voiceCommandsEnabled, forKey: "AMORA_voiceCommandsEnabled")
        defaults.set(preferOnDeviceRecognition, forKey: "AMORA_preferOnDeviceRecognition")
        defaults.set(wakeWordEnabled, forKey: "AMORA_wakeWordEnabled")
        defaults.set(wakeWordEngineKind, forKey: "AMORA_wakeWordEngineKind")
        defaults.set(wakeWordSensitivity, forKey: "AMORA_wakeWordSensitivity")
        defaults.set(porcupineKeywordPath, forKey: "AMORA_porcupineKeywordPath")
        StorageManager.shared.setSecureItem(porcupineAccessKey, forKey: "porcupine-access-key")
        defaults.set(proactiveAmoraEnabled, forKey: "AMORA_proactiveAmoraEnabled")
        defaults.set(proactiveTimerCompletedEnabled, forKey: "AMORA_proactiveTimerCompletedEnabled")
        defaults.set(proactiveTimerNearlyFinishedEnabled, forKey: "AMORA_proactiveTimerNearlyFinishedEnabled")
        defaults.set(proactiveMusicPlaybackEnabled, forKey: "AMORA_proactiveMusicPlaybackEnabled")
        defaults.set(proactiveInactivityReturnEnabled, forKey: "AMORA_proactiveInactivityReturnEnabled")
        defaults.set(proactiveBatteryCriticalEnabled, forKey: "AMORA_proactiveBatteryCriticalEnabled")
        StorageManager.shared.setSecureItem(aiApiKey, forKey: "ai-api-key")
    }
}

enum Theme: String, CaseIterable, Codable, Sendable {
    case midnight = "Midnight"
    case ocean = "Ocean"
    case bubblegum = "Bubblegum"
    case matrix = "Matrix"
    case minimal = "Minimal"
}
