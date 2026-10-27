import XCTest
@testable import AMORA

final class MascotReactionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppState.shared.settings.animationIntensity = 1.0
            AMORARobot.shared.resetForTesting()
            AppState.shared.stateManager.resetToIdle()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppState.shared.settings.animationIntensity = 1.0
            AMORARobot.shared.resetForTesting()
            AppState.shared.stateManager.resetToIdle()
        }
        super.tearDown()
    }

    @MainActor
    func testMascotReactionEnumProperties() {
        let reactions = MascotReaction.allCases
        XCTAssertEqual(reactions.count, 5)

        for reaction in reactions {
            XCTAssertFalse(reaction.displayName.isEmpty)
            XCTAssertFalse(reaction.badgeText.isEmpty)
            XCTAssertFalse(reaction.badgeIcon.isEmpty)
            XCTAssertFalse(reaction.expressiveMessage.isEmpty)
            XCTAssertFalse(reaction.accessibilityDescription.isEmpty)
            XCTAssertNotNil(reaction.sound)
        }

        XCTAssertEqual(MascotReaction.affection.badgeText, "Love")
        XCTAssertEqual(MascotReaction.affection.badgeIcon, "heart.fill")
        XCTAssertEqual(MascotReaction.affection.state, .affection)
        XCTAssertEqual(MascotReaction.affection.expression.eyes, .heart)
        XCTAssertEqual(MascotReaction.affection.sound, .love)

        XCTAssertEqual(MascotReaction.excited.badgeText, "Excited")
        XCTAssertEqual(MascotReaction.excited.badgeIcon, "sparkles")
        XCTAssertEqual(MascotReaction.excited.state, .excited)
        XCTAssertEqual(MascotReaction.excited.expression.eyes, .happy)
        XCTAssertEqual(MascotReaction.excited.sound, .excited)

        XCTAssertEqual(MascotReaction.curious.badgeText, "Curious")
        XCTAssertEqual(MascotReaction.curious.badgeIcon, "eye.fill")
        XCTAssertEqual(MascotReaction.curious.state, .curious)
        XCTAssertEqual(MascotReaction.curious.expression.eyes, .normal)
        XCTAssertEqual(MascotReaction.curious.sound, .click)

        XCTAssertEqual(MascotReaction.grumpy.badgeText, "Grumpy")
        XCTAssertEqual(MascotReaction.grumpy.badgeIcon, "face.dashed")
        XCTAssertEqual(MascotReaction.grumpy.state, .grumpy)
        XCTAssertEqual(MascotReaction.grumpy.expression.eyes, .grumpy)
        XCTAssertEqual(MascotReaction.grumpy.expression.mouth, .flat)
        XCTAssertEqual(MascotReaction.grumpy.sound, .grumpy)

        XCTAssertEqual(MascotReaction.sad.badgeText, "Sad")
        XCTAssertEqual(MascotReaction.sad.badgeIcon, "cloud.rain.fill")
        XCTAssertEqual(MascotReaction.sad.state, .sad)
        XCTAssertEqual(MascotReaction.sad.expression.eyes, .sad)
        XCTAssertEqual(MascotReaction.sad.sound, .sad)
    }

    @MainActor
    func testNormalReactionCycle() {
        let robot = AMORARobot.shared
        var now = Date()

        let first = robot.reactToClick(now: now)
        XCTAssertEqual(first, .affection)
        XCTAssertEqual(robot.activeReaction, .affection)

        now = now.addingTimeInterval(1.6)
        let second = robot.reactToClick(now: now)
        XCTAssertEqual(second, .excited)
        XCTAssertEqual(robot.activeReaction, .excited)

        now = now.addingTimeInterval(1.6)
        let third = robot.reactToClick(now: now)
        XCTAssertEqual(third, .curious)
        XCTAssertEqual(robot.activeReaction, .curious)

        now = now.addingTimeInterval(1.6)
        let fourth = robot.reactToClick(now: now)
        XCTAssertEqual(fourth, .grumpy)
        XCTAssertEqual(robot.activeReaction, .grumpy)

        now = now.addingTimeInterval(1.6)
        let fifth = robot.reactToClick(now: now)
        XCTAssertEqual(fifth, .sad)
        XCTAssertEqual(robot.activeReaction, .sad)

        now = now.addingTimeInterval(1.6)
        let sixth = robot.reactToClick(now: now)
        XCTAssertEqual(sixth, .affection)
        XCTAssertEqual(robot.activeReaction, .affection)
    }

    @MainActor
    func testReactionCycleOnSequentialClicks() {
        let robot = AMORARobot.shared
        var now = Date()

        let first = robot.reactToClick(now: now)
        XCTAssertEqual(first, .affection)
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.expression.eyes, .heart)

        now = now.addingTimeInterval(0.3)
        let second = robot.reactToClick(now: now)
        XCTAssertEqual(second, .excited)
        XCTAssertEqual(robot.activeReaction, .excited)
        XCTAssertEqual(robot.expression.eyes, .happy)

        now = now.addingTimeInterval(0.3)
        let third = robot.reactToClick(now: now)
        // 3rd click within 1.5s triggers grumpy
        XCTAssertEqual(third, .grumpy)
        XCTAssertEqual(robot.activeReaction, .grumpy)
        XCTAssertEqual(robot.expression.eyes, .grumpy)
        XCTAssertEqual(robot.expression.mouth, .flat)

        // After a pause > 1.5s, rapid click counter resets and cycle resumes
        now = now.addingTimeInterval(2.0)
        let fourth = robot.reactToClick(now: now)
        XCTAssertEqual(fourth, .curious)
        XCTAssertEqual(robot.activeReaction, .curious)
    }

    @MainActor
    func testClickDebounceSuppressesRapidSpam() {
        let robot = AMORARobot.shared
        let baseTime = Date()

        // First click succeeds
        let first = robot.reactToClick(now: baseTime)
        XCTAssertEqual(first, .affection)

        // Immediate click within 50ms is debounced
        let spamClick = robot.reactToClick(now: baseTime.addingTimeInterval(0.05))
        XCTAssertNil(spamClick)
        XCTAssertEqual(robot.activeReaction, .affection, "Debounced click must not overwrite active reaction")

        // Another spam click at 150ms is still below threshold (0.22s)
        let spamClick2 = robot.reactToClick(now: baseTime.addingTimeInterval(0.15))
        XCTAssertNil(spamClick2)
        XCTAssertEqual(robot.activeReaction, .affection)

        // Click after 250ms succeeds
        let validClick = robot.reactToClick(now: baseTime.addingTimeInterval(0.25))
        XCTAssertEqual(validClick, .excited)
        XCTAssertEqual(robot.activeReaction, .excited)
    }

    @MainActor
    func testForcedReactionTrigger() {
        let robot = AMORARobot.shared
        let now = Date()

        let reaction = robot.reactToClick(now: now, forcedReaction: .grumpy)
        XCTAssertEqual(reaction, .grumpy)
        XCTAssertEqual(robot.activeReaction, .grumpy)
        XCTAssertEqual(robot.expression.eyes, .grumpy)
        XCTAssertEqual(robot.expression.mouth, .flat)
        XCTAssertEqual(robot.state, .grumpy)
        XCTAssertEqual(robot.activeReactionMessage, "Careful with the visor! 🤖")
    }

    @MainActor
    func testReducedMotionSuppressesPhysicalMovement() {
        let robot = AMORARobot.shared

        // Test with motion enabled (if system reduce motion is not overriding)
        AppState.shared.settings.animationIntensity = 1.0
        if AppState.shared.settings.motionScale > 0 {
            robot.triggerReaction(.grumpy)
            XCTAssertGreaterThan(robot.wigglePhase, 0.0)

            robot.triggerReaction(.excited)
            XCTAssertGreaterThan(robot.bouncePhase, 0.0)
        }

        // Test with user animation intensity at 0 (suppressing all motion)
        AppState.shared.settings.animationIntensity = 0.0
        robot.triggerReaction(.grumpy)
        XCTAssertEqual(robot.wigglePhase, 0.0, "Wiggle must be zero when animation intensity is 0")

        robot.triggerReaction(.excited)
        XCTAssertEqual(robot.bouncePhase, 0.0, "Bounce must be zero when animation intensity is 0")

        // Visual expression still updates under reduce motion
        XCTAssertEqual(robot.expression.eyes, .happy)
        XCTAssertEqual(robot.activeReaction, .excited)
    }

    @MainActor
    func testActiveReactionGuardsAgainstAmbientIdleOverrides() {
        let robot = AMORARobot.shared
        robot.triggerReaction(.affection)
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.expression.eyes, .heart)

        // Ambient idle or watching state changes should not wipe out the active click reaction
        robot.updateExpression(for: .watching)
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.expression.eyes, .heart)

        robot.updateExpression(for: .hover)
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.expression.eyes, .heart)
    }

    @MainActor
    func testHighPriorityAlertOverridesActiveReaction() {
        let robot = AMORARobot.shared
        robot.triggerReaction(.affection)
        XCTAssertEqual(robot.activeReaction, .affection)

        // System alert (priority 80 >= 80) overrides click reaction immediately
        robot.updateExpression(for: .alert)
        XCTAssertNil(robot.activeReaction)
        XCTAssertNil(robot.activeReactionMessage)
        XCTAssertEqual(robot.state, .alert)
        XCTAssertEqual(robot.expression.eyes, .wide)
    }

    @MainActor
    func testClearActiveReactionRestoresPreviousState() {
        let robot = AMORARobot.shared

        // Set an ambient state first
        robot.updateExpression(for: .focused)
        XCTAssertEqual(robot.state, .focused)

        // User clicks and triggers a reaction
        robot.triggerReaction(.affection)
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.state, .affection)

        // When reaction clears, it reverts to the pre-reaction state
        robot.clearActiveReaction()
        XCTAssertNil(robot.activeReaction)
        XCTAssertNil(robot.activeReactionMessage)
        XCTAssertEqual(robot.state, .focused)
    }
}
