import XCTest
import Speech
import AVFoundation
@testable import AMORA

@MainActor
final class VoiceCommandsV1Tests: XCTestCase {
    private var mockEngine: MockSpeechEngine!
    private var service: VoiceCommandService!
    private var assistant: AssistantManager!

    override func setUp() async throws {
        try await super.setUp()
        mockEngine = MockSpeechEngine(permissionState: .authorized)
        assistant = AssistantManager(provider: UnavailableAIProvider(kind: .local), providerIsInjected: true)
        service = VoiceCommandService(engine: mockEngine, assistant: assistant)
    }

    override func tearDown() async throws {
        service.cancelListening()
        mockEngine = nil
        service = nil
        assistant = nil
        try await super.tearDown()
    }

    // MARK: - 1. State Lifecycle & Initial Conditions

    func testInitialStateIsReady() {
        XCTAssertEqual(service.state, .ready)
        XCTAssertFalse(service.isListening)
        XCTAssertFalse(service.isProcessing)
        XCTAssertEqual(service.currentTranscript, "")
        XCTAssertEqual(service.audioLevel, 0.0)
        XCTAssertNil(service.lastErrorMessage)
    }

    // MARK: - 2. Permissions & Availability Handling

    func testPermissionDeniedTransitionsToDeniedState() async {
        let deniedEngine = MockSpeechEngine(permissionState: .denied(description: "Microphone permission is denied."))
        service.configure(engine: deniedEngine)

        await service.startListening()

        if case .permissionDenied(let reason) = service.state {
            XCTAssertTrue(reason.contains("Microphone permission is denied"))
        } else {
            XCTFail("Expected .permissionDenied state, got \(service.state)")
        }
        XCTAssertFalse(service.isListening)
        XCTAssertEqual(AMORARobot.shared.expression, .concerned())
    }

    func testSpeechUnavailableTransitionsToUnavailableState() async {
        mockEngine.isAvailable = false
        await service.startListening()

        if case .unavailable(let reason) = service.state {
            XCTAssertTrue(reason.contains("unavailable"))
        } else {
            XCTFail("Expected .unavailable state, got \(service.state)")
        }
        XCTAssertFalse(service.isListening)
        XCTAssertEqual(AMORARobot.shared.expression, .concerned())
    }

    // MARK: - 3. Session Start & Mascot Integration

    func testStartListeningTransitionsToListeningAndUpdatesMascot() async {
        await service.startListening()

        XCTAssertTrue(service.isListening)
        XCTAssertTrue(mockEngine.wasStartCalled)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .listening)
        XCTAssertEqual(AMORARobot.shared.expression, Expression(
            eyes: .normal,
            eyeOffset: CGPoint(x: 0, y: -2),
            mouth: .neutral,
            blinkProgress: 0,
            headTilt: 0.18,
            antennaPulse: 0.8
        ))
    }

    func testMascotStatePriorityWhileListening() async {
        await service.startListening()
        XCTAssertEqual(AppState.shared.stateManager.currentState, .listening)

        // Try transitioning to lower priority states (hover: 60, watching: 30)
        AppState.shared.stateManager.transition(to: .hover)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .listening, "Listening state (priority 79) must not be overridden by hover (priority 60)")

        // Personality engine ambient state check
        let ambient = PersonalityEngine.shared.currentAmbientState()
        XCTAssertEqual(ambient, .listening)
    }

    // MARK: - 4. Interim Transcripts & Audio Levels

    func testPartialTranscriptStreamUpdatesLiveState() async {
        await service.startListening()

        mockEngine.simulatePartialResult("How much battery")
        XCTAssertEqual(service.currentTranscript, "How much battery")
        if case .listening(_, let partial) = service.state {
            XCTAssertEqual(partial, "How much battery")
        } else {
            XCTFail("Expected .listening state, got \(service.state)")
        }

        mockEngine.simulatePartialResult("How much battery do I have left?")
        XCTAssertEqual(service.currentTranscript, "How much battery do I have left?")
    }

    func testAudioLevelStreamUpdatesLiveLevel() async {
        await service.startListening()

        mockEngine.simulateAudioLevel(0.68)
        XCTAssertEqual(service.audioLevel, 0.68, accuracy: 0.01)
        if case .listening(let level, _) = service.state {
            XCTAssertEqual(level, 0.68, accuracy: 0.01)
        } else {
            XCTFail("Expected .listening state, got \(service.state)")
        }
    }

    // MARK: - 5. Submission & Assistant Execution

    func testStopAndSubmitFinalizesAndSubmitsToAssistant() async {
        await service.startListening()
        mockEngine.simulatePartialResult("How much battery do I have?")

        service.stopAndSubmit()
        XCTAssertTrue(mockEngine.wasStopCalled)

        // Allow task to process
        try? await Task.sleep(nanoseconds: 50_000_000)

        if case .completed(let transcript, let message) = service.state {
            XCTAssertEqual(transcript, "How much battery do I have?")
            XCTAssertTrue(message.contains("Battery is at"), "Expected battery response, got: \(message)")
        } else {
            XCTFail("Expected .completed state, got \(service.state)")
        }
    }

    func testFinalResultFromEngineTriggersSubmission() async {
        await service.startListening()
        mockEngine.simulateFinalResult("How much battery do I have?")

        try? await Task.sleep(nanoseconds: 50_000_000)

        if case .completed(let transcript, let message) = service.state {
            XCTAssertEqual(transcript, "How much battery do I have?")
            XCTAssertTrue(message.contains("Battery is at"))
        } else {
            XCTFail("Expected .completed state, got \(service.state)")
        }
    }

    func testSilenceTimeoutAutoSubmits() async {
        service.silenceTimeoutSeconds = 0.05
        await service.startListening()
        mockEngine.simulatePartialResult("How much battery do I have?")

        // Wait slightly longer than silenceTimeoutSeconds
        try? await Task.sleep(nanoseconds: 120_000_000)

        if case .completed(let transcript, _) = service.state {
            XCTAssertEqual(transcript, "How much battery do I have?")
        } else {
            XCTFail("Expected auto-submission after silence, got \(service.state)")
        }
    }

    func testDuplicateSubmissionGuardPreventsDoubleExecution() async {
        await service.startListening()
        mockEngine.simulatePartialResult("How much battery do I have?")

        service.stopAndSubmit()
        service.stopAndSubmit() // Second immediate call

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Verify conversation history has only 1 exchange
        let userMessages = assistant.conversation.messages.filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1, "Duplicate submission guard must prevent executing the same voice request twice")
    }

    // MARK: - 6. Cancellation & Empty Speech

    func testCancelListeningDiscardsTranscriptAndRestoresAmbient() async {
        await service.startListening()
        mockEngine.simulatePartialResult("Start a 25 minute timer")

        service.cancelListening()

        XCTAssertTrue(mockEngine.wasCancelCalled)
        XCTAssertEqual(service.currentTranscript, "")
        XCTAssertEqual(service.state, .cancelled)

        // Verify no message was added to conversation
        XCTAssertTrue(assistant.conversation.messages.isEmpty)
    }

    func testEmptySpeechDoesNotTriggerAssistant() async {
        await service.startListening()

        service.stopAndSubmit()

        XCTAssertEqual(service.state, .ready)
        XCTAssertTrue(assistant.conversation.messages.isEmpty)
    }

    // MARK: - 7. Errors & Recovery

    func testRecognitionErrorTransitionsToFailed() async {
        await service.startListening()

        let testError = NSError(domain: "test.speech", code: 99, userInfo: [NSLocalizedDescriptionKey: "Microphone stream failed"])
        mockEngine.simulateError(testError)

        if case .failed(let message) = service.state {
            XCTAssertEqual(message, "Microphone stream failed")
        } else {
            XCTFail("Expected .failed state, got \(service.state)")
        }
        XCTAssertEqual(service.lastErrorMessage, "Microphone stream failed")
        XCTAssertEqual(AMORARobot.shared.expression, .concerned())
    }

    // MARK: - 8. Deterministic Action Integration

    func testVoiceCommandDeterministicTimer() async {
        await service.startListening()
        mockEngine.simulateFinalResult("Start a 10 minute timer")

        for _ in 0..<50 {
            if case .completed = service.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        if case .completed(_, let response) = service.state {
            XCTAssertTrue(response.localizedCaseInsensitiveContains("timer"), "Expected timer confirmation, got: \(response)")
            XCTAssertTrue(TimerService.shared.isRunning)
        } else {
            XCTFail("Expected .completed, got \(service.state)")
        }

        TimerService.shared.stopTimer()
    }

    func testVoiceCommandDeterministicFileShelfList() async {
        await service.startListening()
        mockEngine.simulateFinalResult("What files are on my file shelf?")

        for _ in 0..<50 {
            if case .completed = service.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        if case .completed(_, let response) = service.state {
            XCTAssertFalse(response.isEmpty)
            XCTAssertTrue(response.localizedCaseInsensitiveContains("shelf") || response.localizedCaseInsensitiveContains("empty") || response.localizedCaseInsensitiveContains("item"))
        } else {
            XCTFail("Expected .completed, got \(service.state)")
        }
    }

    func testVoiceCommandConsequentialConfirmationRequired() async {
        await service.startListening()
        mockEngine.simulateFinalResult("Clear file shelf")

        // Wait for coordinator to enter awaitingConfirmation
        for _ in 0..<40 {
            if AmoraActionExecutionCoordinator.shared.state == .awaitingConfirmation { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(AmoraActionExecutionCoordinator.shared.state, .awaitingConfirmation)
        XCTAssertNotNil(AmoraActionExecutionCoordinator.shared.pendingConfirmation)
        XCTAssertTrue(AmoraActionExecutionCoordinator.shared.pendingConfirmation?.prompt.localizedCaseInsensitiveContains("clear") ?? false)

        // Deny confirmation safely
        AmoraActionExecutionCoordinator.shared.cancelPendingAction()

        for _ in 0..<40 {
            if case .completed = service.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        if case .completed(_, let response) = service.state {
            XCTAssertTrue(response.localizedCaseInsensitiveContains("cancel") || response.localizedCaseInsensitiveContains("confirmation"), "Expected cancellation notice, got: \(response)")
        } else {
            XCTFail("Expected .completed, got \(service.state)")
        }
    }

    // MARK: - 9. Settings & Preferences

    func testPreferencesVoiceCommandsSettings() {
        let store = SettingsStore()
        XCTAssertTrue(store.voiceCommandsEnabled)
        XCTAssertTrue(store.preferOnDeviceRecognition)

        store.voiceCommandsEnabled = false
        XCTAssertFalse(store.voiceCommandsEnabled)

        store.preferOnDeviceRecognition = false
        XCTAssertFalse(store.preferOnDeviceRecognition)
    }

    // MARK: - 10. Native Apple Speech Engine Safety

    func testAppleSpeechEnginePermissionCheckDoesNotCrash() {
        let appleEngine = AppleSpeechEngine()
        let status = appleEngine.checkPermissions()
        // Status should be valid enum without throwing or crashing
        XCTAssertNotNil(status.userFacingDescription)
        XCTAssertNotNil(appleEngine.recognitionModeDescription)
    }
}
