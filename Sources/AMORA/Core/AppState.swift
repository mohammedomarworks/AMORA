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
        Task {
            await storage.load()
            settings.load()
        }
    }

    func handleLaunch() {
        stateManager.transition(to: .idle)
        AMORAContext.shared.refreshFromServices()
        AMORAEventCenter.shared.emit(.launched)
    }

    func handleTerminate() {
        Task {
            await storage.save()
        }
        settings.save()
    }
}
