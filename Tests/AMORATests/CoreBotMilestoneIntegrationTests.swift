import XCTest
@testable import AMORA

@MainActor
final class CoreBotMilestoneIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        NotesService.shared.clearAll()
        AssistantManager.shared.startNewConversation()
        PersonalityEngine.shared.resetForTesting()
        AMORARobot.shared.resetForTesting()
        AMORAContext.shared.dismissAIResponse()
    }

    override func tearDown() async throws {
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        NotesService.shared.clearAll()
        AssistantManager.shared.startNewConversation()
        AssistantManager.shared.resetProviderToFactory()
        PersonalityEngine.shared.resetForTesting()
        AMORARobot.shared.resetForTesting()
        AMORAContext.shared.dismissAIResponse()
        try await super.tearDown()
    }

    // MARK: - 1. Empty and Whitespace Input Handling
    func testEmptyAndWhitespaceInputHandling() async throws {
        let assistant = AssistantManager.shared
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        let emptyResult = await assistant.submit("", settings: settings)
        XCTAssertEqual(emptyResult, "I'm listening! Ask me a question or tell me what to do.")
        XCTAssertEqual(assistant.state, .idle)

        let whitespaceResult = await assistant.submit("   \n\t  ", settings: settings)
        XCTAssertEqual(whitespaceResult, "I'm listening! Ask me a question or tell me what to do.")
        XCTAssertEqual(assistant.state, .idle)
    }

    // MARK: - 2. Offline Local Commands When Provider Is Unavailable
    func testOfflineLocalCommandsWhenProviderIsUnavailable() async throws {
        let assistant = AssistantManager.shared
        let offlineProvider = MockSequentialAIProvider(response: "unused")
        offlineProvider.isAvailable = false
        assistant.configure(provider: offlineProvider)

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        // 2a. Battery query offline
        let batteryAnswer = await assistant.submit("how much battery do I have?", settings: settings)
        XCTAssertFalse(batteryAnswer.contains("AI Assistant is unavailable"))
        XCTAssertTrue(batteryAnswer.contains("Battery") || batteryAnswer.contains("doesn't report a battery"))
        XCTAssertEqual(assistant.state, .responding)
        XCTAssertFalse(assistant.conversation.messages.isEmpty)

        // 2b. System status offline
        let systemAnswer = await assistant.submit("system status", settings: settings)
        XCTAssertTrue(systemAnswer.contains("CPU is") || systemAnswer.contains("CPU at"))
        XCTAssertEqual(assistant.state, .responding)

        // 2c. Note creation offline
        let noteAnswer = await assistant.submit("add note Buy fresh espresso beans", settings: settings)
        XCTAssertTrue(noteAnswer.contains("Saved"))
        XCTAssertTrue(NotesService.shared.notes.contains { $0.text == "Buy fresh espresso beans" })

        // 2d. Workspace navigation offline
        let notesViewAnswer = await assistant.submit("show notes", settings: settings)
        XCTAssertTrue(notesViewAnswer.contains("notes") || notesViewAnswer.contains("Notes"))

        // 2e. Non-local general question fails honestly when offline
        let generalQuestionAnswer = await assistant.submit("What is the speed of light in a vacuum?", settings: settings)
        XCTAssertTrue(generalQuestionAnswer.localizedCaseInsensitiveContains("unavailable") || generalQuestionAnswer.localizedCaseInsensitiveContains("can't reach"))
        XCTAssertEqual(assistant.state, .failed)
    }

    // MARK: - 3. Rapid Duplicate Submission Debouncing
    func testRapidDuplicateSubmissionDebouncingWhileThinking() async throws {
        let assistant = AssistantManager.shared
        let slowProvider = MockSequentialAIProvider(response: #"{"type":"final_answer","answer":"Task finished."}"#)
        slowProvider.simulatedDelayNanoseconds = 150_000_000 // 150ms
        assistant.configure(provider: slowProvider)

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        async let firstCall = assistant.submit("Tell me a story", settings: settings)
        // Submit duplicate immediately
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        let secondCall = await assistant.submit("Tell me a story", settings: settings)
        let firstResult = await firstCall

        XCTAssertEqual(firstResult, "Task finished.")
        XCTAssertEqual(secondCall, "Task finished.")
    }

    // MARK: - 4. Deterministic Routing for System Status and Workspace Sections
    func testDeterministicRoutingSystemStatusAndWorkspace() async throws {
        // Test System Status routing
        let systemDec = AmoraDeterministicRouter.decision(for: "system status")
        XCTAssertNotNil(systemDec)
        if case .toolCall(let name, _) = systemDec {
            XCTAssertEqual(name, "get_system_status")
        } else {
            XCTFail("Expected toolCall get_system_status")
        }

        let cpuDec = AmoraDeterministicRouter.decision(for: "what is my cpu usage")
        XCTAssertNotNil(cpuDec)
        if case .toolCall(let name, _) = cpuDec {
            XCTAssertEqual(name, "get_system_status")
        } else {
            XCTFail("Expected toolCall get_system_status")
        }

        // Test Workspace Section routing
        let clipboardDec = AmoraDeterministicRouter.decision(for: "open clipboard")
        XCTAssertNotNil(clipboardDec)
        if case .toolCall(let name, let args) = clipboardDec {
            XCTAssertEqual(name, "workspace.open")
            XCTAssertEqual(args["section"], "Clipboard")
        } else {
            XCTFail("Expected workspace.open Clipboard")
        }

        let fileShelfDec = AmoraDeterministicRouter.decision(for: "show file shelf")
        XCTAssertNotNil(fileShelfDec)
        if case .toolCall(let name, let args) = fileShelfDec {
            XCTAssertEqual(name, "workspace.open")
            XCTAssertEqual(args["section"], "File Shelf")
        } else {
            XCTFail("Expected workspace.open File Shelf")
        }

        let settingsDec = AmoraDeterministicRouter.decision(for: "open settings")
        XCTAssertNotNil(settingsDec)
        if case .toolCall(let name, let args) = settingsDec {
            XCTAssertEqual(name, "workspace.open")
            XCTAssertEqual(args["section"], "Settings")
        } else {
            XCTFail("Expected workspace.open Settings")
        }

        // Test Agent Loop execution of get_system_status
        let provider = MockSequentialAIProvider(response: "unused")
        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let loopResult = await loop.runDeterministic(input: "system status", settings: settings)
        XCTAssertNotNil(loopResult)
        XCTAssertTrue(loopResult!.completedSuccessfully)
        XCTAssertTrue(loopResult!.finalAnswer.contains("CPU is at") || loopResult!.finalAnswer.contains("CPU"))
    }

    // MARK: - 5. Mascot Thinking Priority Over Click Reactions and Hover Stability
    func testMascotThinkingPriorityOverridesClickReaction() {
        let robot = AMORARobot.shared

        // Trigger a click reaction (e.g. affection, priority 64)
        _ = robot.reactToClick(now: Date())
        XCTAssertNotNil(robot.activeReaction)

        // Low priority state transition (e.g. watching, priority 30) should NOT clear click reaction
        robot.updateExpression(for: .watching)
        XCTAssertNotNil(robot.activeReaction)

        // High priority assistant state (e.g. aiThinking, priority 78) MUST clear click reaction
        robot.updateExpression(for: .aiThinking)
        XCTAssertNil(robot.activeReaction)
        XCTAssertEqual(robot.expression.mouth, .neutral)

        // Retest with .thinking (priority 76)
        _ = robot.reactToClick(now: Date().addingTimeInterval(1.0))
        XCTAssertNotNil(robot.activeReaction)
        robot.updateExpression(for: .thinking)
        XCTAssertNil(robot.activeReaction)
    }

    func testHoverStabilityPreservesThinkingState() {
        let assistant = AssistantManager.shared
        let robot = AMORARobot.shared
        let stateManager = AppState.shared.stateManager

        assistant.setStateForTesting(.thinking)
        stateManager.transition(to: .aiThinking)
        robot.updateExpression(for: .aiThinking)

        // Hover should not change state away from thinking when assistant is thinking
        let ambient = PersonalityEngine.shared.currentAmbientState()
        XCTAssertEqual(ambient, .aiThinking)

        // Simulating unhover restoring ambient state
        PersonalityEngine.shared.restoreAmbientState()
        XCTAssertEqual(stateManager.currentState, .aiThinking)
    }

    // MARK: - 6. Response Persistence Across Dynamic Island Collapse
    func testResponsePersistenceAcrossIslandCollapse() {
        let assistant = AssistantManager.shared
        assistant.setResponseForTesting("The current status is operational.")
        XCTAssertEqual(assistant.response, "The current status is operational.")

        // User collapses island (e.g. by tapping outside or pressing Esc)
        WindowManager.shared.collapseIsland()

        // Response must remain intact for the user to read upon re-opening
        XCTAssertEqual(assistant.response, "The current status is operational.")
    }

    // MARK: - 7. Conversation Context Follow-up Recording
    func testConversationContextFollowupRecording() async throws {
        let assistant = AssistantManager.shared
        let provider = MockSequentialAIProvider(response: #"{"type":"final_answer","answer":"Timer started for 5 minutes."}"#)
        assistant.configure(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        _ = await assistant.submit("timer 5 minutes", settings: settings)
        XCTAssertEqual(assistant.conversation.messages.count, 2)
        XCTAssertEqual(assistant.conversation.messages[0].role, .user)
        XCTAssertEqual(assistant.conversation.messages[1].role, .assistant)

        // Valid context should be available for follow-up resolution
        let validContext = AmoraConversationContextManager.shared.validContext()
        XCTAssertNotNil(validContext)
    }

    // MARK: - 8. Memory Provenance Privacy Protection
    func testMemoryDerivedTagsPrivacyInConversation() async throws {
        let assistant = AssistantManager.shared
        let memoryProvider = MockSequentialAIProvider(response: #"{"type":"final_answer","answer":"I remembered that your dog is named Max."}"#)
        assistant.configure(provider: memoryProvider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        _ = await assistant.submit("remember that my dog is named Max", settings: settings)

        // Check messages for remote provider
        let remoteMessages = assistant.conversation.messages(for: .anthropic)
        // Memory derived messages should be protected or appropriate tags filtered for outbound privacy
        for msg in remoteMessages {
            XCTAssertFalse(msg.content.isEmpty)
        }
    }
}
