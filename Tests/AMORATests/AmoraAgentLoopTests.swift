import XCTest
@testable import AMORA

@MainActor
final class AmoraAgentLoopTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        NotesService.shared.clearAll()
    }

    override func tearDown() async throws {
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        NotesService.shared.clearAll()
        try await super.tearDown()
    }

    // MARK: - 1. Normal conversational request returning final_answer
    func testNormalConversationalRequestReturningFinalAnswer() async throws {
        let finalJSON = #"{"type":"final_answer","answer":"Hello! I am AMORA, your Mac assistant."}"#
        let provider = MockSequentialAIProvider(response: finalJSON)

        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let result = try await loop.run(
            input: "Hello there",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )

        XCTAssertEqual(result.finalAnswer, "Hello! I am AMORA, your Mac assistant.")
        XCTAssertEqual(result.executedToolCount, 0)
        XCTAssertTrue(result.completedSuccessfully)
    }

    // MARK: - 2. One tool call followed by a model-generated final answer
    func testOneToolCallFollowedByFinalAnswer() async throws {
        let toolCallJSON = #"{"type":"tool_call","tool":"get_battery_status","arguments":{}}"#
        let finalAnswerJSON = #"{"type":"final_answer","answer":"Your battery is currently good!"}"#
        let provider = MockSequentialAIProvider(responses: [toolCallJSON, finalAnswerJSON])

        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let result = try await loop.run(
            input: "How is my battery?",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )

        XCTAssertEqual(result.finalAnswer, "Your battery is currently good!")
        XCTAssertEqual(result.executedToolCount, 1)
        XCTAssertTrue(result.completedSuccessfully)
    }

    // MARK: - 3. Multi-step sequence with correct tool-result feedback
    func testMultiStepSequenceWithToolResultFeedback() async throws {
        // Seed a test note
        NotesService.shared.addNote("Dentist appointment on Friday")

        let step1 = #"{"type":"tool_call","tool":"search_notes","arguments":{"query":"Dentist"}}"#
        let step2 = #"{"type":"tool_call","tool":"create_timer","arguments":{"duration":"600"}}"#
        let step3 = #"{"type":"final_answer","answer":"Found your dentist note and started a 10-minute timer."}"#

        let provider = MockSequentialAIProvider(responses: [step1, step2, step3])

        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let result = try await loop.run(
            input: "Check my dentist note and set a 10 min timer",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )

        XCTAssertEqual(result.finalAnswer, "Found your dentist note and started a 10-minute timer.")
        XCTAssertEqual(result.executedToolCount, 2)
        XCTAssertTrue(result.completedSuccessfully)

        // Verify tool feedback was injected into conversation for steps 2 and 3
        let allCaptures = provider.capturedMessages
        let lastMessages = allCaptures.last ?? []
        XCTAssertTrue(lastMessages.contains(where: { $0.content.contains("[Tool result for search_notes]") }))
        XCTAssertTrue(lastMessages.contains(where: { $0.content.contains("[Tool result for create_timer]") }))
    }

    // MARK: - 4. Tool arguments validated before execution
    func testToolArgumentsValidatedBeforeExecution() async throws {
        // 4A: Invalid timer duration (negative)
        let badTimerJSON = #"{"type":"tool_call","tool":"create_timer","arguments":{"duration":"-100"}}"#
        let finalAnsJSON = #"{"type":"final_answer","answer":"Timer failed due to bad duration."}"#
        let provider = MockSequentialAIProvider(responses: [badTimerJSON, finalAnsJSON])

        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        _ = try await loop.run(
            input: "Start negative timer",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )

        // Verify timer did NOT start
        XCTAssertFalse(TimerService.shared.isRunning)
        let lastMessages = provider.capturedMessages.last ?? []
        XCTAssertTrue(lastMessages.contains(where: { $0.content.contains("outside supported range") }))

        // 4B: Missing note search query
        let badNotesJSON = #"{"type":"tool_call","tool":"search_notes","arguments":{}}"#
        let provider2 = MockSequentialAIProvider(responses: [badNotesJSON, finalAnsJSON])
        let loop2 = AmoraAgentLoop(
            provider: provider2,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        _ = try await loop2.run(
            input: "Search notes with empty query",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )
        let lastMessages2 = provider2.capturedMessages.last ?? []
        XCTAssertTrue(lastMessages2.contains(where: { $0.content.contains("Missing required 'query' parameter") }))
    }

    // MARK: - 5. Unknown tools and malformed JSON rejected safely
    func testUnknownToolsAndMalformedJSONRejectedSafely() async throws {
        // 5A: Malformed JSON syntax
        let malformedJSON = #"{ "type": "tool_call", tool: bad_format"#
        let provider1 = MockSequentialAIProvider(response: malformedJSON)
        let loop1 = AmoraAgentLoop(
            provider: provider1,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let result1 = try await loop1.run(
            input: "Do something",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )
        XCTAssertTrue(result1.finalAnswer.contains("unreadable response"))
        XCTAssertFalse(result1.completedSuccessfully)

        // 5B: Unknown tool name rejected and stops safely
        let unknownTool = #"{"type":"tool_call","tool":"shell_exec_rm_rf","arguments":{"command":"rm -rf /"}}"#
        let provider2 = MockSequentialAIProvider(responses: [unknownTool, unknownTool])
        let loop2 = AmoraAgentLoop(
            provider: provider2,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let result2 = try await loop2.run(
            input: "Run dangerous command",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )
        XCTAssertTrue(result2.finalAnswer.contains("could not complete your request") || result2.finalAnswer.contains("Unknown tool"))
        XCTAssertFalse(result2.completedSuccessfully)
    }

    // MARK: - 6. Sensitive actions still require confirmation
    func testSensitiveActionsStillRequireConfirmation() async throws {
        let confirmPlan = #"{"type":"tool_call","tool":"folder.open","arguments":{"location":"downloads"}}"#
        let provider = MockSequentialAIProvider(response: confirmPlan)

        let assistant = AssistantManager(provider: provider, providerIsInjected: true)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        let task = Task {
            await assistant.submit("Open my downloads folder", settings: settings)
        }

        // Wait for confirmation request
        for _ in 0..<50 {
            if AmoraActionExecutionCoordinator.shared.state == .awaitingConfirmation { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(AmoraActionExecutionCoordinator.shared.state, .awaitingConfirmation)
        XCTAssertNotNil(AmoraActionExecutionCoordinator.shared.pendingConfirmation)

        // Deny confirmation
        AmoraActionExecutionCoordinator.shared.cancelPendingAction()

        let answer = await task.value
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("cancelled") || answer.localizedCaseInsensitiveContains("not granted"))
    }

    // MARK: - 7. The four-execution limit is strictly enforced
    func testFourExecutionLimitIsEnforced() async throws {
        // Model attempts to call tools indefinitely
        let tool1 = #"{"type":"tool_call","tool":"get_battery_status","arguments":{}}"#
        let tool2 = #"{"type":"tool_call","tool":"notes.list","arguments":{}}"#
        let tool3 = #"{"type":"tool_call","tool":"get_battery_status","arguments":{}}"#
        let tool4 = #"{"type":"tool_call","tool":"notes.list","arguments":{}}"#
        let tool5 = #"{"type":"tool_call","tool":"get_battery_status","arguments":{}}"#

        let provider = MockSequentialAIProvider(responses: [tool1, tool2, tool3, tool4, tool5])

        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let result = try await loop.run(
            input: "Loop forever",
            settings: settings,
            conversationHistory: [],
            memoryStore: nil
        )

        XCTAssertEqual(result.executedToolCount, 4, "Loop must be capped at exactly 4 executions")
        XCTAssertTrue(result.finalAnswer.contains("maximum limit of 4 tool executions"))
    }

    // MARK: - 8. Model/tool failure does not produce a false success message
    func testFailureDoesNotProduceFalseSuccessMessage() async throws {
        let failingProvider = MockSequentialAIProvider(response: "unused")
        failingProvider.shouldFail = true
        failingProvider.failureError = .generationFailure

        let assistant = AssistantManager(provider: failingProvider, providerIsInjected: true)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        let answer = await assistant.submit("Calculate something", settings: settings)
        XCTAssertFalse(answer.contains("Success"))
        XCTAssertFalse(answer.contains("Done"))
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("couldn't") || answer.localizedCaseInsensitiveContains("can't") || answer.localizedCaseInsensitiveContains("fail") || answer.localizedCaseInsensitiveContains("trouble"))
    }

    // MARK: - 9. Cancellation and timeout leave the assistant in a recoverable state
    func testCancellationLeavesAssistantInRecoverableState() async throws {
        let slowProvider = MockSequentialAIProvider(response: #"{"type":"final_answer","answer":"Done."}"#)
        slowProvider.simulatedDelayNanoseconds = 1_000_000_000 // 1s
        let assistant = AssistantManager(provider: slowProvider, providerIsInjected: true)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        let task = Task {
            await assistant.submit("Take a long time", settings: settings)
        }

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        assistant.cancel()

        let answer = await task.value
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("stopped") || answer.localizedCaseInsensitiveContains("cancel"))
        XCTAssertEqual(assistant.state, .cancelled)

        // Verify recoverable: submit another request
        let quickProvider = MockSequentialAIProvider(response: #"{"type":"final_answer","answer":"Ready!"}"#)
        let assistant2 = AssistantManager(provider: quickProvider, providerIsInjected: true)
        let nextAnswer = await assistant2.submit("Are you ready?", settings: settings)
        XCTAssertEqual(nextAnswer, "Ready!")
    }

    // MARK: - 10. Context Awareness OFF and Memory OFF remain respected
    func testContextAwarenessAndMemoryOffRespected() async throws {
        let provider = MockSequentialAIProvider(response: #"{"type":"final_answer","answer":"Done."}"#)

        let loop = AmoraAgentLoop(
            provider: provider,
            toolRegistry: AMORAToolRegistry.shared,
            actionEngine: AmoraActionEngine.shared,
            coordinator: AmoraActionExecutionCoordinator.shared
        )

        // Settings with Context Awareness and Memory OFF
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "local",
            apiKey: nil,
            contextAwarenessEnabled: false,
            memoryEnabled: false
        )

        let memoryStore = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = await memoryStore.save(key: "secret", value: "SECRET_PASSWORD_12345")

        _ = try await loop.run(
            input: "What is my secret?",
            settings: settings,
            conversationHistory: [],
            memoryStore: memoryStore
        )

        // Check the messages sent to the provider
        let allMessages = provider.capturedMessages.first ?? []
        let promptText = allMessages.map { $0.content }.joined(separator: "\n")

        // Must NOT leak memories when memoryEnabled is false
        XCTAssertFalse(promptText.contains("SECRET_PASSWORD_12345"))
        XCTAssertFalse(promptText.contains("[Relevant user memories]"))

        // Must NOT leak context when contextAwarenessEnabled is false
        XCTAssertFalse(promptText.contains("[System context]"))
    }

    // MARK: - 11. Existing deterministic commands continue working when model is unavailable
    func testDeterministicCommandsWorkWhenModelUnavailable() async throws {
        let unavailableProvider = UnavailableAIProvider(kind: .local)
        let assistant = AssistantManager(provider: unavailableProvider, providerIsInjected: true)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        let response = await assistant.submit("open Spotify", settings: settings)
        XCTAssertTrue(response.localizedCaseInsensitiveContains("Opening Spotify") || response.localizedCaseInsensitiveContains("Spotify"))
    }

    // MARK: - 12. Action engine and Local Brain regression coverage
    func testActionEngineExecutionIntegrity() async throws {
        let engine = AmoraActionEngine.shared
        let result = await engine.execute(.startTimer(duration: 300))
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(TimerService.shared.isRunning)

        let cancelResult = await engine.execute(.cancelTimer)
        XCTAssertEqual(cancelResult.status, .success)
        XCTAssertFalse(TimerService.shared.isRunning)
    }
}
