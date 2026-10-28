import XCTest
import Speech
import AVFoundation
@testable import AMORA

@MainActor
final class WakeWordV1Tests: XCTestCase {
    private var mockWakeEngine: MockWakeWordEngine!
    private var mockSpeechEngine: MockSpeechEngine!
    private var wakeService: WakeWordService!
    private var voiceService: VoiceCommandService!
    private var assistant: AssistantManager!

    override func setUp() async throws {
        try await super.setUp()
        AppState.shared.settings.wakeWordEnabled = false
        mockWakeEngine = MockWakeWordEngine(isAvailable: true)
        mockSpeechEngine = MockSpeechEngine(permissionState: .authorized)
        assistant = AssistantManager(provider: UnavailableAIProvider(kind: .local), providerIsInjected: true)
        voiceService = VoiceCommandService(engine: mockSpeechEngine, assistant: assistant)
        wakeService = WakeWordService(engine: mockWakeEngine)

        // Connect the test instances together
        wakeService.onWakeWordActivated = { [weak voiceService] res in
            await voiceService?.startListening(initialBuffers: res.bufferedAudio, isWakeWordActivation: true)
        }
        voiceService.onVoiceSessionEnded = { [weak wakeService] in
            wakeService?.notifyVoiceSessionEnded()
        }
    }

    override func tearDown() async throws {
        wakeService.stop()
        voiceService.cancelListening()
        AppState.shared.settings.wakeWordEnabled = false
        mockWakeEngine = nil
        mockSpeechEngine = nil
        wakeService = nil
        voiceService = nil
        assistant = nil
        try await super.tearDown()
    }

    // MARK: - 1. Initial State & Permissions

    func testInitialStateIsDisabled() {
        XCTAssertEqual(wakeService.state, .disabled)
        XCTAssertFalse(wakeService.isStandby)
        XCTAssertFalse(wakeService.isCapturingAudio)
        XCTAssertNil(wakeService.lastErrorMessage)
        XCTAssertEqual(wakeService.state.statusTitle, "Disabled")
    }

    func testDisabledWhenSettingsFalse() {
        AppState.shared.settings.wakeWordEnabled = false
        wakeService.startIfEnabled()
        XCTAssertEqual(wakeService.state, .disabled)
        XCTAssertFalse(mockWakeEngine.wasStartCalled)
    }

    func testStandbyActivationWhenAuthorized() {
        AppState.shared.settings.wakeWordEnabled = true
        wakeService.startIfEnabled()

        XCTAssertTrue(mockWakeEngine.wasStartCalled)
        XCTAssertTrue(mockWakeEngine.isListening)
        if case .standby(let name) = wakeService.state {
            XCTAssertEqual(name, mockWakeEngine.engineName)
        } else {
            XCTFail("Expected .standby state, got \(wakeService.state)")
        }
        XCTAssertTrue(wakeService.isStandby)
        XCTAssertTrue(wakeService.isCapturingAudio)
        XCTAssertEqual(wakeService.state.statusTitle, "Active Standby")
    }

    func testUnavailableEngineTransitionsToUnavailable() {
        mockWakeEngine.isAvailable = false
        AppState.shared.settings.wakeWordEnabled = true
        wakeService.startIfEnabled()

        if case .unavailable(let reason) = wakeService.state {
            XCTAssertTrue(reason.contains("unavailable"))
        } else {
            XCTFail("Expected .unavailable state, got \(wakeService.state)")
        }
        XCTAssertFalse(wakeService.isStandby)
        XCTAssertFalse(wakeService.isCapturingAudio)
    }

    // MARK: - 2. Wake Word Detection & Voice Command Handoff

    func testWakeWordDetectionTriggersListeningAndUpdatesMascot() async {
        AppState.shared.settings.wakeWordEnabled = true
        wakeService.startIfEnabled()
        XCTAssertTrue(wakeService.isStandby)

        // Simulate wake word detection "AMORA"
        mockWakeEngine.simulateWakeWordDetected(wakePhrase: "AMORA", confidence: 0.95)

        // Should pause wake engine during active voice session
        XCTAssertTrue(mockWakeEngine.wasPauseCalled)
        XCTAssertEqual(wakeService.state, .activeVoiceSession)

        // Mascot state should update to listening
        XCTAssertEqual(AppState.shared.stateManager.currentState, .listening)
        XCTAssertEqual(AMORARobot.shared.expression, Expression(
            eyes: .normal,
            eyeOffset: CGPoint(x: 0, y: -2),
            mouth: .neutral,
            blinkProgress: 0,
            headTilt: 0.18,
            antennaPulse: 0.8
        ))

        // Give the async task a moment to invoke VoiceCommandService.shared
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotNil(wakeService.lastDetectionTime)
    }

    // MARK: - 3. Continuous Utterance & Audio Buffer Handoff

    func testContinuousUtteranceBuffersHandoff() async {
        // Create dummy audio buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) else {
            XCTFail("Failed to allocate AVAudioPCMBuffer")
            return
        }
        pcmBuffer.frameLength = 512

        // Start voice service with initialBuffers and isWakeWordActivation
        await voiceService.startListening(initialBuffers: [pcmBuffer], isWakeWordActivation: true)

        XCTAssertTrue(voiceService.isListening)
        XCTAssertTrue(voiceService.isWakeWordActivation)
        XCTAssertTrue(mockSpeechEngine.wasStartCalled)
        XCTAssertEqual(mockSpeechEngine.lastInitialBuffers.count, 1)
        XCTAssertEqual(mockSpeechEngine.lastInitialBuffers.first?.frameLength, 512)
    }

    // MARK: - 4. Leading Wake Word Stripping

    func testLeadingWakeWordStrippingVariations() {
        // Pure wake phrase -> empty
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "AMORA"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "amora"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "Amora!"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "Amora,"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "Hey Amora,"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "Ok Amora"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "Okay Amora:"), "")
        XCTAssertEqual(VoiceCommandService.stripLeadingWakeWord(from: "Hi Amora!"), "")

        // Continuous utterance with trailing command
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "AMORA, set a timer for ten minutes"),
            "set a timer for ten minutes"
        )
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "Amora what is the weather in Tokyo?"),
            "what is the weather in Tokyo?"
        )
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "Hey Amora, open my downloads folder"),
            "open my downloads folder"
        )
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "Okay Amora pause music"),
            "pause music"
        )

        // Preserves internal mentions of Amora
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "Tell Amora that I love her"),
            "Tell Amora that I love her"
        )
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "Remind Amora to backup files"),
            "Remind Amora to backup files"
        )
        XCTAssertEqual(
            VoiceCommandService.stripLeadingWakeWord(from: "Search for Amora on Google"),
            "Search for Amora on Google"
        )
    }

    func testContinuousUtteranceLeadingWakeWordStrippedOnSubmission() async {
        await voiceService.startListening(initialBuffers: [], isWakeWordActivation: true)
        XCTAssertTrue(voiceService.isWakeWordActivation)

        // Simulate recognizer emitting full continuous utterance
        mockSpeechEngine.simulateFinalResult("Amora, set a timer for 5 minutes")

        // In processing, transcript should be stripped of leading "Amora, "
        if case .processing(let transcript) = voiceService.state {
            XCTAssertEqual(transcript, "set a timer for 5 minutes")
        } else {
            XCTFail("Expected .processing state with stripped command, got \(voiceService.state)")
        }
    }

    func testWakePhraseFollowedByPauseStaysInListening() async {
        await voiceService.startListening(initialBuffers: [], isWakeWordActivation: true)
        XCTAssertTrue(voiceService.isWakeWordActivation)

        // The user said "Amora" and paused. Recognizer only heard "Amora" so far.
        mockSpeechEngine.simulatePartialResult("Amora")
        XCTAssertEqual(voiceService.currentTranscript, "Amora")

        // User finishes pausing, then says their command
        mockSpeechEngine.simulatePartialResult("Amora what time is it")
        XCTAssertEqual(voiceService.currentTranscript, "Amora what time is it")

        mockSpeechEngine.simulateFinalResult("Amora what time is it")

        if case .processing(let transcript) = voiceService.state {
            XCTAssertEqual(transcript, "what time is it")
        } else {
            XCTFail("Expected .processing state, got \(voiceService.state)")
        }
    }

    // MARK: - 5. Automatic Return to Standby Lifecycle

    func testReturnToStandbyAfterVoiceCommandCancelled() async {
        AppState.shared.settings.wakeWordEnabled = true
        wakeService.configure(engine: mockWakeEngine)
        wakeService.startIfEnabled()
        XCTAssertTrue(wakeService.isStandby)

        // Simulate wake word triggered
        wakeService.handleWakeWordDetected(WakeWordDetectionResult(
            wakePhrase: "AMORA",
            confidence: 0.9,
            timestamp: Date(),
            bufferedAudio: []
        ))
        XCTAssertEqual(wakeService.state, .activeVoiceSession)

        // User cancels voice listening
        voiceService.cancelListening()

        // Wait for notifyVoiceSessionEnded to restore standby
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(mockWakeEngine.wasResumeCalled)
    }

    // MARK: - 6. Pause, Resume, and Privacy Controls

    func testPauseAndResumeControls() {
        AppState.shared.settings.wakeWordEnabled = true
        wakeService.startIfEnabled()
        XCTAssertTrue(wakeService.isStandby)

        wakeService.pause()
        XCTAssertEqual(wakeService.state, .paused)
        XCTAssertFalse(wakeService.isCapturingAudio)
        XCTAssertTrue(mockWakeEngine.wasPauseCalled)
        XCTAssertEqual(wakeService.state.statusTitle, "Paused")

        wakeService.resume()
        XCTAssertTrue(wakeService.isStandby)
        XCTAssertTrue(wakeService.isCapturingAudio)
        XCTAssertTrue(mockWakeEngine.wasResumeCalled)
    }

    func testDisabledWakeWordStopsMicrophone() {
        AppState.shared.settings.wakeWordEnabled = true
        wakeService.startIfEnabled()
        XCTAssertTrue(wakeService.isStandby)

        wakeService.stop()
        XCTAssertEqual(wakeService.state, .disabled)
        XCTAssertFalse(wakeService.isCapturingAudio)
        XCTAssertTrue(mockWakeEngine.wasStopCalled)
    }

    func testManualMicButtonWorksWhenWakeWordDisabled() async {
        AppState.shared.settings.wakeWordEnabled = false
        wakeService.startIfEnabled()
        XCTAssertEqual(wakeService.state, .disabled)

        // User taps mic button manually
        await voiceService.startListening()
        XCTAssertTrue(voiceService.isListening)
        XCTAssertFalse(voiceService.isWakeWordActivation)
        XCTAssertTrue(mockSpeechEngine.wasStartCalled)
    }

    // MARK: - 7. Ring Audio Buffer Safety & Bounded Memory

    func testRingAudioBufferCapacityAndSnapshotSafety() {
        let buffer = RingAudioBuffer(maxDurationSeconds: 1.0)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        for _ in 0..<10 {
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
            pcm.frameLength = 1600
            buffer.append(pcm)
        }

        let snapshot = buffer.snapshot()
        XCTAssertGreaterThan(snapshot.count, 0)
        XCTAssertLessThanOrEqual(snapshot.count, 11)

        // Clear buffer
        buffer.clear()
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.snapshot().count, 0)

        // Snapshot is an independent copy and remains intact
        XCTAssertGreaterThan(snapshot.count, 0)
    }

    // MARK: - 8. Porcupine Engine Configuration Checks

    func testPorcupineUnconfiguredThrowsInformativeError() {
        let porcupine = PorcupineWakeWordEngine(accessKey: "", keywordPath: nil)
        XCTAssertFalse(porcupine.isAvailable)

        XCTAssertThrowsError(try porcupine.start(onWakeWordDetected: { _ in }, onError: { _ in })) { error in
            guard let wakeError = error as? WakeWordError,
                  case .porcupineUnconfigured(let msg) = wakeError else {
                XCTFail("Expected .porcupineUnconfigured error, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("AccessKey is missing"))
            XCTAssertTrue(msg.contains("console.picovoice.ai"))
        }
    }

    func testPorcupineMissingModelThrowsInformativeError() {
        let porcupine = PorcupineWakeWordEngine(accessKey: "test-valid-key", keywordPath: "/nonexistent/amora.ppn")
        XCTAssertTrue(porcupine.isAvailable)

        XCTAssertThrowsError(try porcupine.start(onWakeWordDetected: { _ in }, onError: { _ in })) { error in
            guard let wakeError = error as? WakeWordError,
                  case .porcupineModelMissing(let msg) = wakeError else {
                XCTFail("Expected .porcupineModelMissing error, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains(".ppn model file not found"))
            XCTAssertTrue(msg.contains("Native On-Device"))
        }
    }

    // MARK: - 9. Native Acoustic Keyword Spotter VAD and Cooldown

    func testNativeAcousticEngineAvailabilityAndName() {
        let native = NativeAcousticWakeWordEngine()
        XCTAssertTrue(native.isAvailable)
        XCTAssertEqual(native.wakePhrase, "AMORA")
        XCTAssertEqual(native.engineName, "Native Acoustic (On-Device)")
    }

    func testNativeAcousticSilenceDoesNotTriggerWakeWord() {
        let native = NativeAcousticWakeWordEngine()
        var detected = false
        native.processAudioBuffer(AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!, frameCapacity: 1024)!)
        try? native.start(onWakeWordDetected: { _ in detected = true }, onError: { _ in })
        // Feed silence buffer (all 0 samples)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        pcm.frameLength = 1024
        // channel data is initialized to zeros

        native.processAudioBuffer(pcm)
        XCTAssertFalse(detected)
        native.stop()
    }

    // MARK: - 10. Preferences Persistence

    func testPreferencesWakeWordPersistence() {
        let defaults = UserDefaults(suiteName: "AMORAWakeWordTestDefaults")!
        defaults.removePersistentDomain(forName: "AMORAWakeWordTestDefaults")

        let store = SettingsStore()
        store.wakeWordEnabled = true
        store.wakeWordEngineKind = WakeWordEngineKind.porcupine.rawValue
        store.wakeWordSensitivity = 0.85
        store.porcupineKeywordPath = "/Users/test/Amora.ppn"
        store.porcupineAccessKey = "test-secret-key"

        store.save(defaults: defaults)

        let reloaded = SettingsStore()
        reloaded.load(defaults: defaults)

        XCTAssertTrue(reloaded.wakeWordEnabled)
        XCTAssertEqual(reloaded.wakeWordEngineKind, WakeWordEngineKind.porcupine.rawValue)
        XCTAssertEqual(reloaded.wakeWordSensitivity, 0.85, accuracy: 0.001)
        XCTAssertEqual(reloaded.porcupineKeywordPath, "/Users/test/Amora.ppn")
        XCTAssertEqual(reloaded.porcupineAccessKey, "test-secret-key")

        defaults.removePersistentDomain(forName: "AMORAWakeWordTestDefaults")
    }
}
