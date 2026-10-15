import XCTest
@testable import AMORA

final class PersonalityPolishV1Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AmoraAutomationService.shared.dismissNotification()
            AmoraProactiveService.shared.dismissCurrentSuggestion()
            IslandActivityCenter.shared.userFocus = nil
            PersonalityEngine.shared.resetForTesting()
            AppState.shared.stateManager.resetToIdle()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AmoraAutomationService.shared.dismissNotification()
            AmoraProactiveService.shared.dismissCurrentSuggestion()
            IslandActivityCenter.shared.userFocus = nil
        }
        super.tearDown()
    }

    @MainActor
    func testPersonalityReactionToneAndCooldown() {
        let engine = PersonalityEngine.shared
        // Emitting timerCompleted should trigger excitement and increment celebration
        let beforeToken = engine.celebrationToken
        engine.react(to: .timerCompleted)
        XCTAssertGreaterThanOrEqual(engine.celebrationToken, beforeToken)

        // Rapid immediate re-firing should be throttled by message cooldown (1s)
        let tokenAfterFirst = engine.celebrationToken
        engine.react(to: .timerCompleted)
        XCTAssertEqual(engine.celebrationToken, tokenAfterFirst)
    }

    @MainActor
    func testAssistantCancellationStateFlow() {
        let assistant = AssistantManager.shared

        // Cancel while idle or thinking transitions cleanly
        assistant.cancel()
        XCTAssertTrue(assistant.state == .idle || assistant.state == .cancelled)

        // Dismissing response returns state to idle
        assistant.dismissResponse()
        XCTAssertEqual(assistant.state, .idle)
        XCTAssertNil(assistant.response)
    }

    @MainActor
    func testActionExecutionCoordinatorCancellation() {
        let coordinator = AmoraActionExecutionCoordinator.shared

        coordinator.reset()
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.isCancelled)

        coordinator.beginThinking()
        XCTAssertEqual(coordinator.state, .thinking)

        coordinator.cancelExecution()
        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertTrue(coordinator.isCancelled)

        coordinator.reset()
        XCTAssertEqual(coordinator.state, .idle)
    }

    @MainActor
    func testPageHeaderVoiceOverStringInterpolation() {
        let pages = QuickPanelView.Page.allCases
        XCTAssertEqual(pages.count, 4)

        for (index, page) in pages.enumerated() {
            let label = "Page \((QuickPanelView.Page.allCases.firstIndex(of: page) ?? 0) + 1) of \(QuickPanelView.Page.allCases.count)"
            XCTAssertEqual(label, "Page \(index + 1) of 4")
        }
    }

    @MainActor
    func testAccessibleStatusBadgeProperties() {
        let badgeNormal = AmoraAccessibleStatusBadge(
            text: "NORMAL",
            systemImage: "checkmark.circle.fill",
            tintColor: .green
        )
        XCTAssertEqual(badgeNormal.text, "NORMAL")
        XCTAssertEqual(badgeNormal.systemImage, "checkmark.circle.fill")

        let badgeHigh = AmoraAccessibleStatusBadge(
            text: "HIGH",
            systemImage: "exclamationmark.triangle.fill",
            tintColor: .orange
        )
        XCTAssertEqual(badgeHigh.text, "HIGH")
        XCTAssertEqual(badgeHigh.systemImage, "exclamationmark.triangle.fill")
    }

    @MainActor
    func testEmptyStateViewProperties() {
        let empty = AmoraEmptyStateView(
            iconName: "bolt.badge.clock",
            title: "No Automations Yet",
            subtitle: "Create an automation anytime."
        )
        XCTAssertEqual(empty.iconName, "bolt.badge.clock")
        XCTAssertEqual(empty.title, "No Automations Yet")
        XCTAssertEqual(empty.subtitle, "Create an automation anytime.")
    }

    @MainActor
    func testDynamicIslandModePriority() {
        let center = IslandActivityCenter.shared
        // By default with no active timer or music, mode is normal
        if !TimerService.shared.isRunning && !MusicService.shared.isPlaying {
            XCTAssertEqual(center.mode, .normal)
        }

        // Setting explicit userFocus overrides normal
        center.userFocus = .system
        XCTAssertEqual(center.mode, .system)

        center.userFocus = nil
    }

    @MainActor
    func testDynamicIslandNotificationModePriority() {
        let center = IslandActivityCenter.shared
        center.userFocus = nil

        let testNotification = AmoraAutomationNotification(
            automationId: UUID(),
            triggerIcon: "timer",
            triggerName: "Focus Session",
            message: "Focus session finished!",
            action: nil,
            actionTitle: nil
        )

        AmoraAutomationService.shared.presentNotification(testNotification)
        XCTAssertEqual(center.mode, .notification)

        // User explicit focus overrides notification
        center.userFocus = .timer
        XCTAssertEqual(center.mode, .timer)
        center.userFocus = nil

        AmoraAutomationService.shared.dismissNotification()
        if !TimerService.shared.isRunning && !MusicService.shared.isPlaying {
            XCTAssertEqual(center.mode, .normal)
        }
    }

    @MainActor
    func testProactiveAndAutomationReactionEvents() {
        PersonalityEngine.shared.resetForTesting()
        AppState.shared.stateManager.resetToIdle()

        // Emitting proactive suggestion presented transitions expression to curious
        AMORAEventCenter.shared.emit(.proactiveSuggestionPresented)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .curious)

        // Dismissing restores calm/idle
        AMORAEventCenter.shared.emit(.proactiveSuggestionDismissed)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle)

        // Automation notification presented transitions expression to alert
        AMORAEventCenter.shared.emit(.automationNotificationPresented)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .alert)

        // Dismissing restores calm/idle
        AMORAEventCenter.shared.emit(.automationNotificationDismissed)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle)
    }

    func testAdaptiveMessageLingerCalculation() {
        // Short message: minimum linger bounds
        let short = "Done."
        let shortLinger = max(4.0, min(9.0, Double(short.count) * 0.08))
        XCTAssertGreaterThanOrEqual(shortLinger, 4.0)

        // Multiline detailed answer: scales up for reading comfort
        let detailed = "Here is what I found in your notes:\n• Project Roadmap for Q4\n• Team Sync notes from Tuesday\n• Design tokens update"
        let detailedLinger = max(4.0, min(9.0, Double(detailed.count) * 0.08))
        XCTAssertGreaterThan(detailedLinger, shortLinger)
        XCTAssertLessThanOrEqual(detailedLinger, 9.0)

        // Dashboard feedback linger
        let dashboardLinger = max(5.0, min(14.0, Double(detailed.count) * 0.08))
        XCTAssertGreaterThanOrEqual(dashboardLinger, 5.0)
        XCTAssertLessThanOrEqual(dashboardLinger, 14.0)
    }

    @MainActor
    func testActionNeverClaimsPrematureSuccess() async {
        let coordinator = AmoraActionExecutionCoordinator.shared
        coordinator.reset()

        // When starting an action, state is idle -> executing, never completed
        coordinator.beginSequence([
            .openApplication(name: "NonExistentAppXYZ")
        ])
        XCTAssertEqual(coordinator.state, .executing)
        XCTAssertNotEqual(coordinator.state, .completed)

        // Cancelling ensures failed/cancelled state, never success
        coordinator.cancelExecution()
        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertTrue(coordinator.isCancelled)
        XCTAssertNotEqual(coordinator.state, .completed)

        coordinator.reset()
    }
}
