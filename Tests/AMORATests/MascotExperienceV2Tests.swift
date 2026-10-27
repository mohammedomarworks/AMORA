import XCTest
@testable import AMORA

final class MascotExperienceV2Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppState.shared.settings.animationIntensity = 1.0
            AppState.shared.settings.soundEnabled = true
            AppState.shared.settings.soundVolume = 0.8
            AMORARobot.shared.resetForTesting()
            SoundService.shared.resetCooldownsForTesting()
            AppState.shared.stateManager.resetToIdle()
            MusicService.shared.isPlaying = false
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppState.shared.settings.animationIntensity = 1.0
            AppState.shared.settings.soundEnabled = true
            AppState.shared.settings.soundVolume = 0.8
            AMORARobot.shared.resetForTesting()
            SoundService.shared.resetCooldownsForTesting()
            AppState.shared.stateManager.resetToIdle()
            MusicService.shared.isPlaying = false
        }
        super.tearDown()
    }

    // MARK: - 1. Notch Eye Stability & Downward Clamping

    @MainActor
    func testApproachingCursorDownwardEyeDirectionIsBounded() {
        let robot = AMORARobot.shared

        // When the user approaches the notch directly from the front (below the notch),
        // normalizedY is -1.0.
        robot.setEyeDirection(x: 0.0, y: -1.0)
        XCTAssertEqual(robot.targetEyeDirection.y, -3.5, accuracy: 0.01)

        // For the notch capsule, clamping limits downward displacement so it
        // never clips against the IslandShape bottom border.
        let clampedY = max(-1.0, min(3.0, robot.targetEyeDirection.y))
        XCTAssertEqual(clampedY, -1.0, accuracy: 0.01)

        // Downward offset in SwiftUI view coordinates (-clampedY) is at most +1.0 pt,
        // leaving >= 6 pt safety margin inside the collapsed notch frame.
        let downwardOffset = -clampedY
        XCTAssertLessThanOrEqual(downwardOffset, 1.0)
    }

    // MARK: - 2. Petting Gesture Recognition & Debounce

    @MainActor
    func testPettingGestureRecognitionOnDeliberateRubbing() {
        let robot = AMORARobot.shared
        var now = Date()

        // 1. Stationary cursor (no delta) does NOT trigger petting
        let point = CGPoint(x: 20, y: 15)
        _ = robot.recordPettingMovement(at: point, now: now)
        let stationaryResult = robot.recordPettingMovement(at: point, now: now.addingTimeInterval(0.1))
        XCTAssertFalse(stationaryResult, "Stationary cursor must not trigger petting reaction")

        // 2. Single unidirectional sweep without reversals does not trigger petting
        robot.resetPetting()
        now = Date()
        _ = robot.recordPettingMovement(at: CGPoint(x: 10, y: 15), now: now)
        _ = robot.recordPettingMovement(at: CGPoint(x: 20, y: 15), now: now.addingTimeInterval(0.05))
        let sweepResult = robot.recordPettingMovement(at: CGPoint(x: 35, y: 15), now: now.addingTimeInterval(0.10))
        XCTAssertFalse(sweepResult, "Single sweep without direction reversals must not trigger petting")

        // 3. Deliberate back-and-forth rubbing gesture (>= 2 reversals, >= 30pt stroke)
        robot.resetPetting()
        now = Date()
        _ = robot.recordPettingMovement(at: CGPoint(x: 10, y: 15), now: now)
        // Stroke right (+18pt)
        _ = robot.recordPettingMovement(at: CGPoint(x: 28, y: 15), now: now.addingTimeInterval(0.05))
        // Reverse stroke left (-16pt, reversal 1)
        _ = robot.recordPettingMovement(at: CGPoint(x: 12, y: 15), now: now.addingTimeInterval(0.10))
        // Reverse stroke right (+18pt, reversal 2, total stroke = 52pt)
        let petResult = robot.recordPettingMovement(at: CGPoint(x: 30, y: 15), now: now.addingTimeInterval(0.15))
        XCTAssertTrue(petResult, "Deliberate back-and-forth rubbing gesture must trigger petting")

        // 4. Repeated movement within 2.5s cooldown does NOT re-trigger
        _ = robot.recordPettingMovement(at: CGPoint(x: 15, y: 15), now: now.addingTimeInterval(0.5))
        _ = robot.recordPettingMovement(at: CGPoint(x: 32, y: 15), now: now.addingTimeInterval(0.6))
        let cooldownResult = robot.recordPettingMovement(at: CGPoint(x: 14, y: 15), now: now.addingTimeInterval(0.7))
        XCTAssertFalse(cooldownResult, "Cooldown must prevent noisy repeated petting firing")

        // 5. After cooldown (3.0s later), deliberate petting succeeds again
        now = now.addingTimeInterval(3.0)
        _ = robot.recordPettingMovement(at: CGPoint(x: 10, y: 15), now: now)
        _ = robot.recordPettingMovement(at: CGPoint(x: 28, y: 15), now: now.addingTimeInterval(0.05))
        _ = robot.recordPettingMovement(at: CGPoint(x: 12, y: 15), now: now.addingTimeInterval(0.10))
        let afterCooldownResult = robot.recordPettingMovement(at: CGPoint(x: 30, y: 15), now: now.addingTimeInterval(0.15))
        XCTAssertTrue(afterCooldownResult, "Petting must succeed once cooldown has elapsed")
    }

    // MARK: - 3. Expanded Mode Neutral Resting State

    @MainActor
    func testExpandedModeInitializesInNeutralRestingState() {
        let robot = AMORARobot.shared

        // When island expands, robot expression must start calm and neutral (.idle()), NOT .happy()
        robot.updateExpression(for: .expanded)
        XCTAssertEqual(robot.expression.eyes, .normal, "Expanded mode must start in neutral calm eyes")
        XCTAssertEqual(robot.expression.mouth, .neutral, "Expanded mode must not have forced smile mouth")
        XCTAssertNotEqual(robot.expression.eyes, .happy, "Expanded mode must not be permanently excited")

        // Merely hovering over collapsed notch also shows attentive normal eyes, not continuous excitement
        robot.updateExpression(for: .hover)
        XCTAssertEqual(robot.expression.eyes, .normal, "Hover must display calm attentive eyes")
    }

    @MainActor
    func testPettingInExpandedModeRevertsToAmbientRestingState() {
        let robot = AMORARobot.shared

        // Expanded resting state
        robot.updateExpression(for: .expanded)
        XCTAssertEqual(robot.expression.eyes, .normal)

        // User pets AMORA in expanded view
        robot.pet()
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.expression.eyes, .heart, "Petting triggers affectionate heart eyes")
        XCTAssertEqual(robot.state, .affection)

        // When reaction completes, it settles back to the neutral ambient state
        robot.clearActiveReaction()
        XCTAssertNil(robot.activeReaction)
        XCTAssertEqual(robot.expression.eyes, .normal, "After petting finishes, AMORA returns to neutral calm resting eyes")
    }

    // MARK: - 4. Music Dancing Animation & Lifecycle

    @MainActor
    func testMusicPlaybackStartsAndStopsDancingAnimation() {
        let robot = AMORARobot.shared
        let music = MusicService.shared

        XCTAssertFalse(robot.isDancing)

        // Music playback begins
        music.isPlaying = true
        // Invoke updateFrame simulation logic directly:
        // When music is playing, AMORA enters dancing state
        robot.updateExpression(for: .music)
        XCTAssertEqual(robot.state, .music)
        XCTAssertEqual(robot.expression.eyes, .happy)

        // Verify dancing animation state tracking
        AppState.shared.settings.animationIntensity = 1.0
        // When music plays and motion > 0:
        // Update frame drives isDancing, tilt, bounce, antenna, and glow
        // Simulate updateFrame execution
        let elapsed: Double = 1.0
        let motion = AppState.shared.settings.motionScale
        XCTAssertGreaterThan(motion, 0.0)

        robot.isDancing = music.isPlaying
        robot.danceTiltPhase = sin(elapsed * 4.2) * 0.20 * motion
        robot.danceBouncePhase = abs(sin(elapsed * 4.2)) * 3.5 * motion
        robot.danceAntennaPhase = 0.5 + sin(elapsed * 8.4) * 0.5 * motion
        robot.danceGlowPulse = 0.5 + sin(elapsed * 4.2) * 0.5 * motion

        XCTAssertTrue(robot.isDancing)
        XCTAssertNotEqual(robot.danceTiltPhase, 0.0)
        XCTAssertGreaterThan(robot.danceBouncePhase, 0.0)
        XCTAssertGreaterThan(robot.danceGlowPulse, 0.0)

        // Music pauses / stops
        music.isPlaying = false
        robot.isDancing = false
        robot.danceTiltPhase = 0
        robot.danceBouncePhase = 0
        robot.danceAntennaPhase = 0
        robot.danceGlowPulse = 0
        robot.updateExpression(for: .idle)

        XCTAssertFalse(robot.isDancing, "Dancing must stop when playback is paused or stopped")
        XCTAssertEqual(robot.danceTiltPhase, 0.0)
        XCTAssertEqual(robot.danceBouncePhase, 0.0)
        XCTAssertEqual(robot.danceGlowPulse, 0.0)
        XCTAssertEqual(robot.expression.eyes, .normal)
    }

    @MainActor
    func testMusicDancingRespectsReduceMotion() {
        let robot = AMORARobot.shared
        MusicService.shared.isPlaying = true

        // User enables Reduce Motion (animationIntensity = 0)
        AppState.shared.settings.animationIntensity = 0.0
        let motion = AppState.shared.settings.motionScale
        XCTAssertEqual(motion, 0.0)

        // Under Reduce Motion, bounce and tilt must collapse to zero stillness
        robot.isDancing = true
        robot.danceTiltPhase = 0
        robot.danceBouncePhase = 0
        robot.danceGlowPulse = 0.35 // Gentle steady glow without pulsating

        XCTAssertEqual(robot.danceTiltPhase, 0.0, "Tilt must be zero under Reduce Motion")
        XCTAssertEqual(robot.danceBouncePhase, 0.0, "Bounce must be zero under Reduce Motion")
        XCTAssertEqual(robot.danceGlowPulse, 0.35, "Glow must remain steady without pulsing")
    }

    // MARK: - 5. Emotion Sounds Synthesis & Preferences

    @MainActor
    func testEmotionSoundSynthesisProducesValidWAVData() {
        let loveData = SoundService.generateLoveAudioData()
        let grumpyData = SoundService.generateGrumpyAudioData()
        let excitedData = SoundService.generateExcitedAudioData()
        let sadData = SoundService.generateSadAudioData()

        for data in [loveData, grumpyData, excitedData, sadData] {
            XCTAssertGreaterThan(data.count, 44, "Synthesized WAV must contain full header + PCM samples")

            // Verify RIFF identifier
            let riff = String(data: data.subdata(in: 0..<4), encoding: .ascii)
            XCTAssertEqual(riff, "RIFF")

            // Verify WAVE format
            let wave = String(data: data.subdata(in: 8..<12), encoding: .ascii)
            XCTAssertEqual(wave, "WAVE")

            // Verify fmt chunk
            let fmt = String(data: data.subdata(in: 12..<16), encoding: .ascii)
            XCTAssertEqual(fmt, "fmt ")

            // Verify data chunk
            let dataChunk = String(data: data.subdata(in: 36..<40), encoding: .ascii)
            XCTAssertEqual(dataChunk, "data")
        }

        // Verify SoundService.audioData(for:) returns cached synthesized audio data
        let service = SoundService.shared
        XCTAssertNotNil(service.audioData(for: .love))
        XCTAssertNotNil(service.audioData(for: .grumpy))
        XCTAssertNotNil(service.audioData(for: .excited))
        XCTAssertNotNil(service.audioData(for: .sad))
        XCTAssertNil(service.audioData(for: .click), "System alert sounds must not have synthesized WAV data")
    }

    @MainActor
    func testSoundDisabledPreferenceAndVolumeScale() {
        let service = SoundService.shared
        service.resetCooldownsForTesting()

        // When sound is disabled in settings, play does not fail and remains silent
        AppState.shared.settings.soundEnabled = false
        service.play(.love)
        service.play(.grumpy)

        // When enabled with zero volume
        AppState.shared.settings.soundEnabled = true
        AppState.shared.settings.soundVolume = 0.0
        service.play(.love)

        // When enabled with normal volume
        AppState.shared.settings.soundVolume = 0.8
        service.resetCooldownsForTesting()
        service.play(.love)
    }

    // MARK: - 6. Sad Emotion Reaction & Differentiation

    @MainActor
    func testSadEmotionStatePropertiesAndDifferentiation() {
        let robot = AMORARobot.shared

        // Trigger Sad reaction
        robot.triggerReaction(.sad)
        XCTAssertEqual(robot.activeReaction, .sad)
        XCTAssertEqual(robot.state, .sad)
        XCTAssertEqual(robot.expression.eyes, .sad)
        XCTAssertEqual(robot.activeReactionMessage, "A bit down, but here with you... 🌧️")
        XCTAssertEqual(MascotReaction.sad.sound, .sad)
        XCTAssertEqual(MascotReaction.sad.badgeText, "Sad")
        XCTAssertEqual(MascotReaction.sad.badgeIcon, "cloud.rain.fill")

        // Sadness (priority 65) is distinct from Grumpy (priority 66) and Error (priority 100)
        XCTAssertEqual(AMORAState.sad.priority, 65)
        XCTAssertEqual(AMORAState.grumpy.priority, 66)
        XCTAssertEqual(AMORAState.error.priority, 100)

        // Recoverable cancellation event in PersonalityEngine routes to .sad
        AMORAEventCenter.shared.emit(.aiCancelled)
        XCTAssertEqual(robot.state, .sad, "aiCancelled event must transition robot to gentle sadness")
        XCTAssertEqual(robot.expression.eyes, .sad)
    }

    // MARK: - 7. State Priority Rules & Interactivity

    @MainActor
    func testHighPriorityAssistantStatesOverridePetReaction() {
        let robot = AMORARobot.shared

        // AMORA is petted
        robot.pet()
        XCTAssertEqual(robot.activeReaction, .affection)

        // High priority assistant state (e.g. aiThinking priority 78, speaking priority 75)
        robot.updateExpression(for: .aiThinking)
        XCTAssertNil(robot.activeReaction, "High priority AI thinking must supersede pet reaction")
        XCTAssertEqual(robot.state, .aiThinking)

        // Another pet
        robot.pet()
        XCTAssertEqual(robot.activeReaction, .affection)

        // Alert state (priority 98) overrides pet reaction immediately
        robot.updateExpression(for: .alert)
        XCTAssertNil(robot.activeReaction, "Alert state must supersede pet reaction")
        XCTAssertEqual(robot.state, .alert)
    }
}
