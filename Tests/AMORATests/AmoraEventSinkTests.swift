import XCTest
@testable import AMORA

@MainActor
final class AmoraEventSinkTests: XCTestCase {

    override func tearDown() async throws {
        TimerService.shared.eventSink = MacOSAmoraEventSink()
        NotesService.shared.eventSink = MacOSAmoraEventSink()
        BatteryService.shared.eventSink = MacOSAmoraEventSink()
        ClipboardService.shared.eventSink = MacOSAmoraEventSink()
        FileShelfService.shared.eventSink = MacOSAmoraEventSink()
        MusicService.shared.eventSink = MacOSAmoraEventSink()
        AMORACommandRouter.shared.eventSink = MacOSAmoraEventSink()
        try await super.tearDown()
    }

    // MARK: - 1. Mock Event Sink Unit Tests

    func testMockEventSinkRecordsEventsInOrder() {
        let sink = MockAmoraEventSink()
        XCTAssertEqual(sink.count, 0)
        XCTAssertTrue(sink.recordedEvents.isEmpty)
        XCTAssertNil(sink.lastEvent())

        sink.emit(.launched)
        sink.emit(.aiThinking)
        sink.emit(.commandProcessing)
        sink.emit(.commandSucceeded)
        sink.emit(.closed)

        XCTAssertEqual(sink.count, 5)
        XCTAssertEqual(sink.recordedEvents, [
            .launched,
            .aiThinking,
            .commandProcessing,
            .commandSucceeded,
            .closed
        ])
        XCTAssertTrue(sink.contains(.commandProcessing))
        XCTAssertFalse(sink.contains(.timerCompleted))
        XCTAssertEqual(sink.lastEvent(), .closed)

        sink.reset()
        XCTAssertEqual(sink.count, 0)
        XCTAssertTrue(sink.recordedEvents.isEmpty)
        XCTAssertNil(sink.lastEvent())
    }

    // MARK: - 2. macOS Platform Adapter Tests

    func testMacOSAmoraEventSinkDelegatesToEventCenter() {
        let sink = MacOSAmoraEventSink()
        sink.emit(.fileReceived)
        XCTAssertEqual(AMORAContext.shared.currentEvent, .fileReceived)
    }

    // MARK: - 3. Action Engine Event Decoupling Tests

    func testActionEngineEmitsProcessingAndSucceededToInjectedSink() async {
        let mockSink = MockAmoraEventSink()
        let registry = AmoraActionRegistry()
        registry.register(
            AmoraActionDefinition(
                identifier: "media.play",
                name: "Play",
                description: "Play Music",
                handler: { _, _ in .success(actionId: "media.play", message: "All good") }
            )
        )
        let engine = AmoraActionEngine(registry: registry, eventSink: mockSink)

        let result = await engine.execute(.playMusic)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(mockSink.recordedEvents, [.commandProcessing, .commandSucceeded])
    }

    func testActionEngineEmitsProcessingAndFailedForUnregisteredAction() async {
        let mockSink = MockAmoraEventSink()
        let engine = AmoraActionEngine(registry: AmoraActionRegistry(), eventSink: mockSink)

        let result = await engine.execute(.playMusic)

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(mockSink.recordedEvents, [.commandProcessing, .commandFailed])
    }

    func testActionEngineEmitsProcessingAndFailedForInvalidInput() async {
        let mockSink = MockAmoraEventSink()
        let registry = AmoraActionRegistry()
        registry.register(
            AmoraActionDefinition(
                identifier: "media.play",
                name: "Play",
                description: "Play Music",
                validator: { _ in .invalid(reason: "Invalid parameter") },
                handler: { _, _ in .success(actionId: "media.play", message: "ok") }
            )
        )
        let engine = AmoraActionEngine(registry: registry, eventSink: mockSink)

        let result = await engine.execute(.playMusic)

        XCTAssertEqual(result.status, .invalidInput)
        XCTAssertEqual(mockSink.recordedEvents, [.commandProcessing, .commandFailed])
    }

    func testActionEngineSequenceEmitsToInjectedSink() async {
        let mockSink = MockAmoraEventSink()
        let registry = AmoraActionRegistry()
        registry.register(
            AmoraActionDefinition(
                identifier: "media.play",
                name: "Play",
                description: "Play Music",
                handler: { _, _ in .success(actionId: "media.play", message: "Step 1 OK") }
            )
        )
        registry.register(
            AmoraActionDefinition(
                identifier: "media.pause",
                name: "Pause",
                description: "Pause Music",
                handler: { _, _ in .success(actionId: "media.pause", message: "Step 2 OK") }
            )
        )
        let engine = AmoraActionEngine(registry: registry, eventSink: mockSink)

        let results = await engine.executeSequence([.playMusic, .pauseMusic])

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.status == .success })
        XCTAssertEqual(mockSink.recordedEvents, [
            .commandProcessing,
            .commandSucceeded
        ])
    }

    // MARK: - 4. Automation Service Event Decoupling Tests

    func testAutomationServiceNotificationEmitsToInjectedSink() {
        let mockSink = MockAmoraEventSink()
        let service = AmoraAutomationService(
            store: AmoraAutomationStore(storage: AmoraInMemoryAutomationStorage()),
            clock: { Date() },
            eventSink: mockSink
        )

        let notification = AmoraAutomationNotification(
            triggerIcon: "timer",
            triggerName: "Focus Timer",
            message: "Notification test"
        )

        service.presentNotification(notification)
        XCTAssertEqual(mockSink.recordedEvents, [.automationNotificationPresented])

        service.dismissNotification()
        XCTAssertEqual(mockSink.recordedEvents, [
            .automationNotificationPresented,
            .automationNotificationDismissed
        ])
    }

    func testProactiveServiceEmitsToInjectedSinkOnDismiss() async {
        let mockSink = MockAmoraEventSink()
        let service = AmoraProactiveService(
            eventSink: mockSink,
            onSuggestionPresented: { _ in
                mockSink.emit(.proactiveSuggestionPresented)
            }
        )

        let suggestion = AmoraProactiveSuggestion(
            trigger: .batteryCriticallyLow,
            conditionDescription: "Battery below 10%",
            cooldownDuration: 60,
            priority: .high,
            message: "Connect charger soon."
        )

        service.dismissCurrentSuggestion() // No suggestion active -> no emit
        XCTAssertEqual(mockSink.count, 0)

        // Evaluate candidate into currentSuggestion
        final class StubEvaluator: AmoraProactiveEvaluating, @unchecked Sendable {
            let candidate: AmoraProactiveSuggestion
            init(candidate: AmoraProactiveSuggestion) { self.candidate = candidate }
            func evaluate(trigger: AmoraProactiveTrigger, context: AmoraProactiveEvaluationContext) -> AmoraProactiveSuggestion? {
                candidate
            }
        }

        let stubService = AmoraProactiveService(
            evaluator: StubEvaluator(candidate: suggestion),
            eventSink: mockSink,
            onSuggestionPresented: { _ in
                mockSink.emit(.proactiveSuggestionPresented)
            }
        )

        _ = await stubService.evaluateTrigger(.batteryCriticallyLow)
        XCTAssertEqual(mockSink.recordedEvents, [.proactiveSuggestionPresented])

        stubService.dismissCurrentSuggestion()
        XCTAssertEqual(mockSink.recordedEvents, [
            .proactiveSuggestionPresented,
            .proactiveSuggestionDismissed
        ])
    }

    func testAgentLoopInitializesWithCustomSink() async throws {
        let mockSink = MockAmoraEventSink()
        let provider = MockAIProvider(response: #"{"type":"final_answer","answer":"Done"}"#)
        let loop = AmoraAgentLoop(
            provider: provider,
            eventSink: mockSink
        )
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let result = try await loop.run(
            input: "Test input",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )
        XCTAssertTrue(result.completedSuccessfully)
        XCTAssertEqual(result.finalAnswer, "Done")
    }

    // MARK: - 5. Assistant Manager Event Decoupling Tests

    func testAssistantManagerEmitsToInjectedSinkOnCancel() {
        let mockSink = MockAmoraEventSink()
        let provider = MockAIProvider(response: "Mock response")
        let assistant = AssistantManager(
            provider: provider,
            providerIsInjected: true,
            eventSink: mockSink
        )

        assistant.cancel() // Idle cancel does not emit
        XCTAssertEqual(mockSink.count, 0)
    }

    // MARK: - 6. Secondary Feature Services Event Decoupling Tests

    func testTimerServiceEmitsToConfiguredSink() {
        let mockSink = MockAmoraEventSink()
        let service = TimerService.shared
        service.eventSink = mockSink
        service.isSimulationMode = true

        service.startTimer(seconds: 10)
        XCTAssertTrue(mockSink.contains(.timerStarted))

        service.pauseTimer()
        XCTAssertTrue(mockSink.contains(.timerPaused))

        service.resumeTimer()
        XCTAssertTrue(mockSink.contains(.timerResumed))

        service.stopTimer()
    }

    func testNotesServiceEmitsToConfiguredSink() {
        let mockSink = MockAmoraEventSink()
        let service = NotesService.shared
        service.useIsolatedStorage(suiteName: "com.amora.test.eventsink.notes")
        service.eventSink = mockSink

        service.addNote("Hello from decoupled event sink")
        XCTAssertEqual(mockSink.recordedEvents, [.noteCreated])

        service.restoreStandardStorage()
    }

    func testClipboardServiceEmitsToConfiguredSink() {
        let mockSink = MockAmoraEventSink()
        let service = ClipboardService.shared
        service.eventSink = mockSink

        let item = ClipboardItem(text: "Test clipboard text", timestamp: Date())
        service.copyToClipboard(item)

        XCTAssertTrue(mockSink.contains(.clipboardRestored))
    }

    func testFileShelfServiceEmitsToConfiguredSink() {
        let mockSink = MockAmoraEventSink()
        let service = FileShelfService.shared
        service.eventSink = mockSink

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_event_shelf.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        service.addFile(url: tempFile)
        XCTAssertTrue(mockSink.contains(.fileReceived))

        service.removeItem(id: service.items.first(where: { $0.url.path == tempFile.path })?.id ?? UUID())
    }

    func testCommandRouterEmitsToConfiguredSink() {
        let mockSink = MockAmoraEventSink()
        let router = AMORACommandRouter.shared
        router.eventSink = mockSink

        let result = router.execute(.unknown(text: "unsupported command query xyz"))
        XCTAssertEqual(result.message, "I don't know how to do that yet.")
        XCTAssertEqual(mockSink.recordedEvents, [.commandProcessing, .commandFailed])
    }
}
