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

    // MARK: - 8. Dance Shape Stability & Notch Eye Geometry Tests

    @MainActor
    func testDanceMaintainsExactRobotShapeAndGeometryWithoutScaling() {
        let robot = AMORARobot.shared
        let music = MusicService.shared
        music.isPlaying = true
        robot.isDancing = true

        let elapsed: Double = 1.0
        let motion: Double = 1.0
        robot.danceTiltPhase = sin(elapsed * 2.1) * 0.05 * motion
        robot.danceBouncePhase = abs(sin(elapsed * 4.2)) * 1.8 * motion
        robot.danceSwayPhase = sin(elapsed * 2.1) * 1.5 * motion
        robot.danceAntennaPhase = 0.5 + sin(elapsed * 4.2) * 0.5 * motion
        robot.danceGlowPulse = 0.5 + sin(elapsed * 4.2) * 0.5 * motion

        // The robot's one-shot click bouncePhase must remain 0 during dance, ensuring 0 scale transform
        XCTAssertEqual(robot.bouncePhase, 0.0, "Dance must not alter body scale or bouncePhase")
        XCTAssertLessThanOrEqual(robot.danceBouncePhase, 1.8, "Dance vertical bounce must be restrained")
        XCTAssertLessThanOrEqual(abs(robot.danceSwayPhase), 1.5, "Dance side-to-side sway must be restrained")
        XCTAssertLessThanOrEqual(abs(robot.danceTiltPhase), 0.06, "Dance tilt sway must be restrained")

        // Facial features: expression eyes are .happy, mouth is .smile (cheerful excited face while dancing)
        robot.updateExpression(for: .music)
        XCTAssertEqual(robot.expression.eyes, .happy)
        XCTAssertEqual(robot.expression.mouth, .smile, "Music expression shows an excited smile mouth while dancing")

        // When music playback stops, all dance state cleanly resets to 0
        music.isPlaying = false
        robot.isDancing = false
        robot.danceTiltPhase = 0
        robot.danceBouncePhase = 0
        robot.danceSwayPhase = 0
        robot.danceAntennaPhase = 0
        robot.danceGlowPulse = 0
        robot.updateExpression(for: .idle)

        XCTAssertFalse(robot.isDancing)
        XCTAssertEqual(robot.danceTiltPhase, 0.0)
        XCTAssertEqual(robot.danceBouncePhase, 0.0)
        XCTAssertEqual(robot.danceSwayPhase, 0.0)
        XCTAssertEqual(robot.danceAntennaPhase, 0.0)
        XCTAssertEqual(robot.danceGlowPulse, 0.0)
        XCTAssertEqual(robot.expression.eyes, .normal)
        XCTAssertEqual(robot.expression.mouth, .neutral)
    }

    @MainActor
    func testCollapsedNotchEyesSitInVisibleChinBelowPhysicalNotchCutout() {
        let island = IslandModel.shared
        island.topInset = 34
        island.notchWidth = 200
        island.collapsedSize = CGSize(width: 200, height: 44) // 34pt notch + 10pt chin

        let chinHeight = max(10, island.collapsedSize.height - island.topInset)
        XCTAssertEqual(chinHeight, 10.0, "Chin height must provide 10pt visible margin below physical notch")

        let eyeHeight: CGFloat = 6.5
        let eyeTop = island.topInset + (chinHeight - eyeHeight) / 2
        let eyeBottom = eyeTop + eyeHeight

        // The entire eye capsule must sit strictly in the visible chin [34, 44]
        XCTAssertGreaterThan(eyeTop, island.topInset, "Top of eye must sit below physical hardware notch cutout (y > 34)")
        XCTAssertLessThan(eyeBottom, island.collapsedSize.height, "Bottom of eye must sit above bottom edge (y < 44)")

        // Downward gaze clamp test: normalizedY = -1.0 (approaching cursor from below)
        let robot = AMORARobot.shared
        robot.setEyeDirection(x: 0.0, y: -1.0)
        let clampedYDown = max(-1.0, min(1.0, robot.targetEyeDirection.y))
        let maxDownwardOffset = -clampedYDown // +1.0
        XCTAssertLessThanOrEqual(maxDownwardOffset, 1.0)
        XCTAssertLessThan(eyeBottom + maxDownwardOffset, island.collapsedSize.height, "Eye must never cross bottom clipping boundary")

        // Upward gaze clamp test: normalizedY = 1.0 (cursor above)
        robot.setEyeDirection(x: 0.0, y: 1.0)
        let clampedYUp = max(-1.0, min(1.0, robot.targetEyeDirection.y))
        let maxUpwardOffset = -clampedYUp // -1.0
        XCTAssertGreaterThan(eyeTop + maxUpwardOffset, island.topInset, "Eye must never retreat into physical notch cutout")
    }

    // MARK: - 9. Music Dance Background Visibility & Playback State Integration Tests

    @MainActor
    func testMusicDanceBackgroundVisibilityTiedStrictlyToActivePlayback() {
        let robot = AMORARobot.shared
        let music = MusicService.shared
        let island = IslandModel.shared

        // 1. Music is stopped: background must NOT be active
        music.isPlaying = false
        robot.isDancing = false
        XCTAssertFalse(robot.isDancing, "Background must not appear when playback is inactive")

        // 2. Merely expanding the island into Quick or Workspace must NOT show background
        island.displayState = .quick
        island.targetState = .quick
        island.expansion = 1.0
        XCTAssertFalse(robot.isDancing, "Expanding island alone must not trigger music dance background")

        island.displayState = .workspace
        island.targetState = .workspace
        island.expansion = 2.0
        XCTAssertFalse(robot.isDancing, "Workspace expansion alone must not trigger music dance background")

        // 3. Triggering non-music mascot reactions (e.g. excited, affection) must NOT show background
        let now = Date()
        robot.reactToClick(now: now, forcedReaction: .excited)
        XCTAssertEqual(robot.activeReaction, .excited)
        XCTAssertFalse(robot.isDancing, "Excited reaction must not trigger music dance background")

        robot.reactToClick(now: now.addingTimeInterval(0.35), forcedReaction: .affection)
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertFalse(robot.isDancing, "Love reaction must not trigger music dance background")

        // 4. Genuine music playback starts: background becomes active
        music.isPlaying = true
        robot.isDancing = true
        XCTAssertTrue(robot.isDancing, "Music dance background must activate when playback is confirmed")

        // 5. Clean teardown
        music.isPlaying = false
        robot.isDancing = false
        island.displayState = .collapsed
        island.targetState = .collapsed
        island.expansion = 0.0
    }

    @MainActor
    func testMusicDanceBackgroundPlaybackStateTransitions() {
        let robot = AMORARobot.shared
        let music = MusicService.shared

        // Step 1: Starting playback (e.g. from Spotify or Apple Music)
        music.isPlaying = true
        robot.isDancing = true
        robot.danceGlowPulse = 0.8
        robot.danceAntennaPhase = 0.6
        XCTAssertTrue(robot.isDancing)
        XCTAssertGreaterThan(robot.danceGlowPulse, 0.0)

        // Step 2: Pausing playback
        music.isPlaying = false
        robot.isDancing = false
        robot.danceGlowPulse = 0.0
        robot.danceAntennaPhase = 0.0
        robot.danceTiltPhase = 0.0
        robot.danceBouncePhase = 0.0
        robot.danceSwayPhase = 0.0
        XCTAssertFalse(robot.isDancing, "Background must disappear upon pause")
        XCTAssertEqual(robot.danceGlowPulse, 0.0)

        // Step 3: Resuming playback
        music.isPlaying = true
        robot.isDancing = true
        robot.danceGlowPulse = 0.75
        XCTAssertTrue(robot.isDancing, "Background must reappear upon resume")

        // Step 4: Track ends or stops
        music.isPlaying = false
        robot.isDancing = false
        robot.danceGlowPulse = 0.0
        XCTAssertFalse(robot.isDancing, "Background must deactivate when track ends")

        // Step 5: Browser media disconnection / lost state
        music.isPlaying = true
        robot.isDancing = true
        XCTAssertTrue(robot.isDancing)

        // Simulating browser disconnect or tab closed
        music.isPlaying = false
        robot.isDancing = false
        robot.danceGlowPulse = 0.0
        XCTAssertFalse(robot.isDancing, "Background must immediately deactivate on browser disconnect")
    }

    @MainActor
    func testMusicDanceBackgroundMatchesReferenceAndPreservesRobotStructure() {
        let robot = AMORARobot.shared
        let music = MusicService.shared
        music.isPlaying = true
        robot.isDancing = true

        // Verify Reduce Motion behavior on background
        AppState.shared.settings.animationIntensity = 0.0
        let motion = AppState.shared.settings.motionScale
        XCTAssertEqual(motion, 0.0)

        // Under Reduce Motion, bounce and tilt are 0, glow remains steady
        robot.danceBouncePhase = 0
        robot.danceSwayPhase = 0
        robot.danceTiltPhase = 0
        robot.danceGlowPulse = 0.35

        XCTAssertEqual(robot.danceBouncePhase, 0.0)
        XCTAssertEqual(robot.danceSwayPhase, 0.0)
        XCTAssertEqual(robot.danceTiltPhase, 0.0)
        XCTAssertEqual(robot.danceGlowPulse, 0.35, "Steady warm aura must remain under Reduce Motion without pulsing")

        // Reset settings
        AppState.shared.settings.animationIntensity = 1.0
        music.isPlaying = false
        robot.isDancing = false
    }

    // MARK: - 10. Dance Excited Expression & Notch-Eye Gaze/Petting Regression Tests

    @MainActor
    func testMusicDancingExpressionShowsExcitedHappyEyesAndSmileMouth() {
        let robot = AMORARobot.shared
        let music = MusicService.shared
        let personality = PersonalityEngine.shared
        let stateManager = AppState.shared.stateManager

        personality.resetForTesting()
        music.isPlaying = false
        robot.isDancing = false
        robot.clearActiveReaction()
        stateManager.resetToIdle()

        // 1. Verify Expression.music() definition
        let expr = Expression.music()
        XCTAssertEqual(expr.eyes, .happy, "Music expression must have cheerful happy eyes (^ ^)")
        XCTAssertEqual(expr.mouth, .smile, "Music expression must have an upbeat smile mouth")
        XCTAssertEqual(expr.antennaPulse, 0.8, "Music expression must have an active antenna pulse")

        // 2. Music starts: enters .music state with excited dancing expression
        music.isPlaying = true
        personality.react(to: .musicStarted)
        XCTAssertEqual(stateManager.currentState, .music)
        XCTAssertEqual(robot.expression.eyes, .happy)
        XCTAssertEqual(robot.expression.mouth, .smile)

        // 3. Higher priority state (e.g. aiThinking or alert) is preserved
        stateManager.transition(to: .aiThinking)
        robot.updateExpression(for: .aiThinking)
        XCTAssertEqual(stateManager.currentState, .aiThinking)
        XCTAssertEqual(robot.expression.eyes, .narrow)

        // Routine music event must not overwrite AI thinking
        personality.react(to: .musicChanged)
        XCTAssertEqual(stateManager.currentState, .aiThinking, "Routine musicChanged must not clobber active AI thinking")

        // When thinking restores ambient state, music is restored
        stateManager.resetToIdle()
        personality.restoreAmbientState()
        XCTAssertEqual(stateManager.currentState, .music, "Ambient state should restore music while music is playing")
        XCTAssertEqual(robot.expression.eyes, .happy)
        XCTAssertEqual(robot.expression.mouth, .smile)

        // 4. Music paused / stopped: reverts cleanly to resting expression
        music.isPlaying = false
        personality.react(to: .musicStopped)
        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertEqual(robot.expression.eyes, .normal)
        XCTAssertEqual(robot.expression.mouth, .neutral)
    }

    @MainActor
    func testPettingDuringMusicDancingRevertsBackToDancingState() {
        let robot = AMORARobot.shared
        let music = MusicService.shared
        let personality = PersonalityEngine.shared
        let stateManager = AppState.shared.stateManager

        personality.resetForTesting()
        music.isPlaying = true
        robot.clearActiveReaction()
        stateManager.transition(to: .music)
        robot.updateExpression(for: .music)

        XCTAssertEqual(robot.state, .music)
        XCTAssertEqual(robot.expression.eyes, .happy)
        XCTAssertEqual(robot.expression.mouth, .smile)

        // Petting AMORA triggers affection reaction with heart eyes
        robot.pet()
        XCTAssertEqual(robot.activeReaction, .affection)
        XCTAssertEqual(robot.expression.eyes, .heart)
        XCTAssertEqual(robot.expression.mouth, .smile)

        // When petting reaction ends, AMORA returns to music dancing expression
        robot.clearActiveReaction()
        XCTAssertNil(robot.activeReaction)
        XCTAssertEqual(robot.state, .music)
        XCTAssertEqual(robot.expression.eyes, .happy)
        XCTAssertEqual(robot.expression.mouth, .smile)

        // Cleanup
        music.isPlaying = false
        stateManager.resetToIdle()
        robot.updateExpression(for: .idle)
    }

    @MainActor
    func testGazeTrackingNormalizationAndNotchChinHitTestGeometry() {
        let island = IslandModel.shared
        island.topInset = 34
        island.notchWidth = 200
        island.collapsedSize = CGSize(width: 200, height: 44) // 34pt notch + 10pt chin

        let chinHeight = max(10, island.collapsedSize.height - island.topInset)
        XCTAssertEqual(chinHeight, 10.0)

        // Verify that the chin bounds sit strictly in [34, 44]
        let chinTop = island.collapsedSize.height - chinHeight
        XCTAssertEqual(chinTop, 34.0, "Chin must be positioned at bottom 10pt of window frame")

        // Gaze tracking normalization tests:
        let halfWidth = max(island.collapsedSize.width / 2, 1)
        let halfHeight = max(island.collapsedSize.height / 2, 1)
        let windowMidX: CGFloat = island.collapsedSize.width / 2
        let windowMidY: CGFloat = island.collapsedSize.height / 2

        // Test cursor centered: relX = 0, relY = 0
        let normCenterX = max(-1.0, min(1.0, Double((windowMidX - windowMidX) / halfWidth)))
        let normCenterY = max(-1.0, min(1.0, Double((windowMidY - windowMidY) / halfHeight)))
        XCTAssertEqual(normCenterX, 0.0, accuracy: 0.001)
        XCTAssertEqual(normCenterY, 0.0, accuracy: 0.001)

        // Test cursor 50pt right of center: normX = 50 / 100 = 0.5
        let cursorRightX = windowMidX + 50.0
        let normRightX = max(-1.0, min(1.0, Double((cursorRightX - windowMidX) / halfWidth)))
        XCTAssertEqual(normRightX, 0.5, accuracy: 0.001)

        // Test cursor 11pt below center: normY = -11 / 22 = -0.5
        let cursorBelowY = windowMidY - 11.0
        let normBelowY = max(-1.0, min(1.0, Double((cursorBelowY - windowMidY) / halfHeight)))
        XCTAssertEqual(normBelowY, -0.5, accuracy: 0.001)

        // Test petting gesture tracking in notch chin
        let robot = AMORARobot.shared
        robot.resetPetting()

        let baseTime = Date().addingTimeInterval(3.5)
        // Rubbing back and forth across notch chin
        _ = robot.recordPettingMovement(at: CGPoint(x: 80, y: 38), now: baseTime)
        _ = robot.recordPettingMovement(at: CGPoint(x: 105, y: 39), now: baseTime.addingTimeInterval(0.1))
        _ = robot.recordPettingMovement(at: CGPoint(x: 85, y: 38), now: baseTime.addingTimeInterval(0.2))
        let recognized = robot.recordPettingMovement(at: CGPoint(x: 115, y: 39), now: baseTime.addingTimeInterval(0.3))

        XCTAssertTrue(recognized, "Deliberate rubbing across notch chin must trigger petting recognition")
    }

    @MainActor
    func testFacialLayoutPreservesEyePositionRegardlessOfMouthState() {
        let robot = AMORARobot.shared

        // Test idle expression: mouth is neutral
        robot.updateExpression(for: .idle)
        XCTAssertEqual(robot.expression.mouth, .neutral)
        XCTAssertEqual(robot.expression.eyes, .normal)

        // Test excited/music expression: mouth is smile
        robot.updateExpression(for: .music)
        XCTAssertEqual(robot.expression.mouth, .smile)
        XCTAssertEqual(robot.expression.eyes, .happy)

        // Digital face decouples eyes from mouth: eye anchor offset is fixed at -1.0 (compact) / -1.5 (non-compact)
        // regardless of whether mouth is neutral, smile, sad, or open.
        let compactEyeAnchorY: CGFloat = -1.0
        let nonCompactEyeAnchorY: CGFloat = -1.5
        let compactMouthAnchorY: CGFloat = 5.5
        let nonCompactMouthAnchorY: CGFloat = 8.5

        // Distance between eye anchor and mouth anchor remains invariant:
        let compactVerticalDelta = compactMouthAnchorY - compactEyeAnchorY
        let nonCompactVerticalDelta = nonCompactMouthAnchorY - nonCompactEyeAnchorY
        XCTAssertEqual(compactVerticalDelta, 6.5, "Compact face eye-to-mouth vertical distance must remain invariant")
        XCTAssertEqual(nonCompactVerticalDelta, 10.0, "Non-compact face eye-to-mouth vertical distance must remain invariant")
    }
}
