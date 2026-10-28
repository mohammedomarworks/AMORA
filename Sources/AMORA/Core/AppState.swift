import Foundation
import SwiftUI
import Observation

@Observable @MainActor
final class AppState {
    static let shared = AppState()

    let stateManager = AMORAStateManager.shared
    let settings = SettingsStore()
    let storage = StorageManager.shared

    var isQuickPanelOpen: Bool = false
    var isDashboardOpen: Bool = false
    var isPaused: Bool = false

    private init() {
        initialize()
    }

    private func initialize() {
        storage.load()
        settings.load()
    }

    func handleLaunch() {
        stateManager.transition(to: .idle)
        AMORAContext.shared.refreshFromServices()
        AMORAEventCenter.shared.emit(.launched)
        if NSClassFromString("XCTestCase") == nil && settings.wakeWordEnabled {
            WakeWordService.shared.startIfEnabled()
        }
    }

    func handleTerminate() {
        WakeWordService.shared.stop()
        AmoraLlamaCppRuntime.shared.unloadSync()
        ClipboardService.shared.stopPolling()
        SystemMonitorService.shared.stopMonitoring()
        MusicService.shared.stopPolling()
        TimerService.shared.stopTimer()
        AMORARobot.shared.stopAnimations()
        storage.save()
        settings.save()
    }
}
