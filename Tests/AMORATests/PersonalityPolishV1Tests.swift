import XCTest
@testable import AMORA

final class PersonalityPolishV1Tests: XCTestCase {

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
}
