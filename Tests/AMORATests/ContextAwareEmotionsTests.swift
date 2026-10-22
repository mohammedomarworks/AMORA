import XCTest
@testable import AMORA

final class ContextAwareEmotionsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppState.shared.settings.animationIntensity = 1.0
            IslandModel.shared.expansion = 0.0
            IslandModel.shared.targetState = .collapsed
            IslandModel.shared.displayState = .collapsed
            AMORARobot.shared.resetForTesting()
            PersonalityEngine.shared.resetForTesting()
            AppState.shared.stateManager.resetToIdle()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppState.shared.settings.animationIntensity = 1.0
            IslandModel.shared.expansion = 0.0
            IslandModel.shared.targetState = .collapsed
            IslandModel.shared.displayState = .collapsed
            AMORARobot.shared.resetForTesting()
            PersonalityEngine.shared.resetForTesting()
            AppState.shared.stateManager.resetToIdle()
        }
        super.tearDown()
    }

    @MainActor
    func testTaskSuccessReaction() {
        // Command success triggers happy expression and restrained bounce
        AMORAEventCenter.shared.emit(.commandSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .happy)
        XCTAssertEqual(AMORARobot.shared.state, .happy)
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 0.45)
        XCTAssertEqual(AMORARobot.shared.expression.mouth, .smile)

        // Reset and test AI success
        AMORARobot.shared.resetForTesting()
        PersonalityEngine.shared.resetForTesting()
        AppState.shared.stateManager.resetToIdle()

        AMORAEventCenter.shared.emit(.aiSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .aiResponse)
        XCTAssertEqual(AMORARobot.shared.state, .aiResponse)
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 0.45)
    }

    @MainActor
    func testTaskFailureReaction() {
        // Command failure triggers concerned expression and suppresses physical motion
        AMORARobot.shared.playBounce() // simulate prior movement
        XCTAssertGreaterThan(AMORARobot.shared.bouncePhase, 0)

        AMORAEventCenter.shared.emit(.commandFailed)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .concerned)
        XCTAssertEqual(AMORARobot.shared.state, .concerned)
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 0) // zeroed out
        XCTAssertEqual(AMORARobot.shared.wigglePhase, 0)
        // Expression is concerned and respectful, not angry
        XCTAssertEqual(AMORARobot.shared.expression.eyes, .sad)
        XCTAssertEqual(AMORARobot.shared.expression.mouth, .neutral)

        // Reset and test AI failure
        AMORARobot.shared.resetForTesting()
        PersonalityEngine.shared.resetForTesting()
        AppState.shared.stateManager.resetToIdle()

        AMORAEventCenter.shared.emit(.aiFailed)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .aiError)
        XCTAssertEqual(AMORARobot.shared.state, .aiError)
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 0)
    }

    @MainActor
    func testListeningAndThinkingExpression() {
        AMORAEventCenter.shared.emit(.commandProcessing)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .thinking)
        XCTAssertEqual(AMORARobot.shared.state, .thinking)
        XCTAssertGreaterThan(AMORARobot.shared.expression.antennaPulse, 0.4)

        AMORARobot.shared.resetForTesting()
        PersonalityEngine.shared.resetForTesting()
        AppState.shared.stateManager.resetToIdle()

        AMORAEventCenter.shared.emit(.aiThinking)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .aiThinking)
        XCTAssertEqual(AMORARobot.shared.state, .aiThinking)
        XCTAssertGreaterThan(AMORARobot.shared.expression.antennaPulse, 0.4)
    }

    @MainActor
    func testTimerCompletionCelebration() {
        let initialCelebration = PersonalityEngine.shared.celebrationToken

        AMORAEventCenter.shared.emit(.timerCompleted)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .excited)
        XCTAssertEqual(AMORARobot.shared.state, .excited)
        // Celebration bounce is full pop (1.0)
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 1.0)
        XCTAssertGreaterThan(PersonalityEngine.shared.celebrationToken, initialCelebration)
        XCTAssertEqual(PersonalityEngine.shared.message, "Focus session complete! ✨")
    }

    @MainActor
    func testAlertPriorityOverTaskEvents() {
        // Transition to alert state
        AMORAEventCenter.shared.emit(.automationNotificationPresented)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .alert)

        // General task events must NOT override the critical alert
        AMORAEventCenter.shared.emit(.commandProcessing)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .alert)

        AMORAEventCenter.shared.emit(.commandSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .alert)

        AMORAEventCenter.shared.emit(.aiThinking)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .alert)

        AMORAEventCenter.shared.emit(.timerStarted)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .alert)

        // Explicit dismissal of the alert restores normal operation
        AMORAEventCenter.shared.emit(.automationNotificationDismissed)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle)
    }

    @MainActor
    func testDuplicateEventSuppression() {
        // First event transitions state
        AMORAEventCenter.shared.emit(.commandSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .happy)

        // Reset state directly without resetting PersonalityEngine's lastEvent tracking
        AppState.shared.stateManager.resetToIdle()
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle)

        // Immediate duplicate event within 350ms is suppressed
        AMORAEventCenter.shared.emit(.commandSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle, "Rapid duplicate event should be suppressed")
    }

    @MainActor
    func testAmbientStateRecovery() {
        // With timer inactive, music stopped, island closed, ambient state is idle
        XCTAssertEqual(PersonalityEngine.shared.currentAmbientState(), .idle)

        // Enter a temporary state
        AMORAEventCenter.shared.emit(.commandSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .happy)

        // Reverting restores ambient state
        PersonalityEngine.shared.forceRevertForTesting()
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle)

        // If island is expanded, ambient state is expanded
        IslandModel.shared.expansion = 1.0
        IslandModel.shared.targetState = .quick
        IslandModel.shared.displayState = .quick
        XCTAssertEqual(PersonalityEngine.shared.currentAmbientState(), .expanded)

        AMORAEventCenter.shared.emit(.commandFailed)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .concerned)

        PersonalityEngine.shared.forceRevertForTesting()
        XCTAssertEqual(AppState.shared.stateManager.currentState, .expanded)
    }

    @MainActor
    func testIdleMicroReactionAndInteractionWakeup() {
        // Ensure starting calm and idle
        XCTAssertFalse(AMORARobot.shared.isPerformingIdleMicroReaction)

        // Trigger an idle micro-reaction directly
        AMORARobot.shared.triggerIdleMicroReaction(now: Date())
        XCTAssertTrue(AMORARobot.shared.isPerformingIdleMicroReaction)

        // Any user interaction should immediately cancel it and restore ambient
        AMORARobot.shared.noteInteraction()
        XCTAssertFalse(AMORARobot.shared.isPerformingIdleMicroReaction)
        XCTAssertEqual(AMORARobot.shared.targetEyeDirection, .zero)
    }

    @MainActor
    func testReduceMotionCompliance() {
        // When motion scale is 0 (Reduce Motion enabled)
        AppState.shared.settings.animationIntensity = 0.0
        XCTAssertEqual(AppState.shared.settings.motionScale, 0.0)

        AMORARobot.shared.playRestrainedBounce()
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 0.0)

        AMORARobot.shared.playBounce()
        XCTAssertEqual(AMORARobot.shared.bouncePhase, 0.0)

        // But visual expression still works
        AMORAEventCenter.shared.emit(.commandSucceeded)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .happy)
        XCTAssertEqual(AMORARobot.shared.expression.mouth, .smile)
    }
}
