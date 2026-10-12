import XCTest
@testable import AMORA

/// Regression coverage for the Local Agent V1 functional bugfix:
/// 1. Note search returns real matches (never an echoed instruction).
/// 2. Battery status returns real data (never a stale/echoed note response).
/// 3. Timer minutes are converted to seconds correctly (10 min = 600 s, not 10 s).
/// 4. Downloads folder routes through the confirmation flow.
///
/// These use a deterministic MockAIProvider that would otherwise ECHO the
/// instruction back — proving the deterministic-first router keeps the weak model
/// off the critical path for clear, supported requests.
@MainActor
final class AmoraLocalAgentBugfixTests: XCTestCase {

    private func settings() -> AISettingsSnapshot {
        // Context + memory OFF to isolate deterministic routing from the follow-up resolver.
        AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil,
                           contextAwarenessEnabled: false, memoryEnabled: false)
    }

    /// A provider that echoes a fixed, irrelevant answer for every call — the exact
    /// failure mode observed with the 0.5B model.
    private func echoProvider() -> MockAIProvider {
        MockAIProvider(response: #"{"type":"final_answer","answer":"Find your notes"}"#)
    }

    override func setUp() async throws {
        try await super.setUp()
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
    }

    override func tearDown() async throws {
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        try await super.tearDown()
    }

    // MARK: - 1. Note search returns real matches, not an echo

    func testNoteSearchReturnsRealMatches() async {
        let token = "ZZmeetingNoteABC"
        NotesService.shared.addNote("Weekly team \(token) at 10 AM")
        defer { NotesService.shared.notes.filter { $0.text.contains(token) }.forEach { NotesService.shared.deleteNote(id: $0.id) } }

        let assistant = AssistantManager(provider: echoProvider())
        let answer = await assistant.submit("Find my notes about \(token)", settings: settings())

        XCTAssertTrue(answer.contains(token), "Expected the real matching note, got: \(answer)")
        XCTAssertNotEqual(answer, "Find your notes", "Must not echo the model's instruction paraphrase")
    }

    func testNoteSearchNoMatchIsTruthful() async {
        let assistant = AssistantManager(provider: echoProvider())
        let answer = await assistant.submit("Find my notes about zzz_no_such_note_qqq", settings: settings())

        XCTAssertTrue(answer.localizedCaseInsensitiveContains("no notes found"), "Expected an honest no-match response, got: \(answer)")
        XCTAssertNotEqual(answer, "Find your notes")
    }

    // MARK: - 2. Battery returns real data, not the stale note echo

    func testBatteryReturnsRealStatus() async {
        let assistant = AssistantManager(provider: echoProvider())
        let answer = await assistant.submit("How much battery do I have left?", settings: settings())

        XCTAssertTrue(answer.localizedCaseInsensitiveContains("battery"), "Expected real battery data, got: \(answer)")
        XCTAssertFalse(answer.localizedCaseInsensitiveContains("find your notes"), "Must not reuse the stale note echo")
    }

    // MARK: - 3. Consecutive different requests never reuse a stale answer

    func testConsecutiveRequestsDoNotReuseStaleAnswer() async {
        let assistant = AssistantManager(provider: echoProvider())
        let noteAnswer = await assistant.submit("Find my notes about zzz_none_here_qqq", settings: settings())
        let batteryAnswer = await assistant.submit("How much battery do I have left?", settings: settings())

        XCTAssertNotEqual(noteAnswer, batteryAnswer, "Different requests must not share one global/stale answer")
        XCTAssertTrue(batteryAnswer.localizedCaseInsensitiveContains("battery"))
        XCTAssertFalse(batteryAnswer.localizedCaseInsensitiveContains("note"))
    }

    // MARK: - 4. Timer minutes convert to seconds (deterministic router boundary)

    func testDeterministicTimerMinutesConversion() async {
        let loop = AmoraAgentLoop(provider: echoProvider())
        let cases: [(String, Int)] = [
            ("set a timer for 1 minute", 60),
            ("set a timer for 5 minutes", 300),
            ("set a timer for 10 minutes", 600),
            ("start a 25 minute timer", 1500),
            ("set a timer for 90 seconds", 90),
            ("set a timer for 1 hour", 3600)
        ]
        for (input, expected) in cases {
            TimerService.shared.stopTimer()
            let result = await loop.runDeterministic(input: input, settings: settings())
            XCTAssertNotNil(result, "Router should handle: \(input)")
            XCTAssertEqual(TimerService.shared.totalSeconds, expected, "Wrong seconds for '\(input)'")
            XCTAssertTrue(TimerService.shared.isRunning)
        }
        TimerService.shared.stopTimer()
    }

    // MARK: - 5. Timer unit handling at the tool→service boundary (model path)

    func testToolBoundaryTimerUnits() async throws {
        let cases: [(String, Int)] = [
            (#"{"type":"tool_call","tool":"create_timer","arguments":{"minutes":"10"}}"#, 600),
            (#"{"type":"tool_call","tool":"create_timer","arguments":{"seconds":"90"}}"#, 90),
            (#"{"type":"tool_call","tool":"create_timer","arguments":{"minutes":"1"}}"#, 60),
            (#"{"type":"tool_call","tool":"create_timer","arguments":{"hours":"1"}}"#, 3600),
            (#"{"type":"tool_call","tool":"create_timer","arguments":{"duration":"600"}}"#, 600),
            (#"{"type":"tool_call","tool":"create_timer","arguments":{"duration":"10","unit":"minutes"}}"#, 600)
        ]
        for (toolJSON, expected) in cases {
            TimerService.shared.stopTimer()
            let final = #"{"type":"final_answer","answer":"ok"}"#
            let loop = AmoraAgentLoop(provider: MockSequentialAIProvider(responses: [toolJSON, final]))
            _ = try await loop.run(input: "handle this request", settings: settings())
            XCTAssertEqual(TimerService.shared.totalSeconds, expected, "Wrong seconds for \(toolJSON)")
        }
        TimerService.shared.stopTimer()
    }

    func testTimerRejectsInvalidDurations() async throws {
        let bad = ["0", "-100", "999999"]
        for value in bad {
            TimerService.shared.stopTimer()
            let toolJSON = "{\"type\":\"tool_call\",\"tool\":\"create_timer\",\"arguments\":{\"seconds\":\"\(value)\"}}"
            let final = #"{"type":"final_answer","answer":"ok"}"#
            let loop = AmoraAgentLoop(provider: MockSequentialAIProvider(responses: [toolJSON, final]))
            _ = try await loop.run(input: "handle this request", settings: settings())
            XCTAssertFalse(TimerService.shared.isRunning, "Invalid duration '\(value)' must not start a timer")
        }
    }

    // MARK: - 6. Downloads folder requires confirmation; cancel prevents opening

    func testDownloadsFolderConfirmationDeniedPreventsOpen() async throws {
        let assistant = AssistantManager(provider: echoProvider())
        let task = Task { await assistant.submit("Open my Downloads folder", settings: settings()) }

        for _ in 0..<100 {
            if AmoraActionExecutionCoordinator.shared.state == .awaitingConfirmation { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(AmoraActionExecutionCoordinator.shared.state, .awaitingConfirmation,
                       "Opening a folder must request confirmation first")
        XCTAssertNotNil(AmoraActionExecutionCoordinator.shared.pendingConfirmation)

        AmoraActionExecutionCoordinator.shared.cancelPendingAction()
        let answer = await task.value
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("cancelled") || answer.localizedCaseInsensitiveContains("not granted"),
                      "Denied confirmation must not open the folder, got: \(answer)")
    }

    func testDownloadsFolderConfirmationAcceptedExecutes() async throws {
        let assistant = AssistantManager(provider: echoProvider())
        let task = Task { await assistant.submit("Open my Downloads folder", settings: settings()) }

        for _ in 0..<100 {
            if AmoraActionExecutionCoordinator.shared.state == .awaitingConfirmation { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(AmoraActionExecutionCoordinator.shared.state, .awaitingConfirmation)

        AmoraActionExecutionCoordinator.shared.confirmPendingAction()
        let answer = await task.value
        // On the real Mac this opens Downloads; the response must be truthful and
        // must NOT report a cancellation when the user confirmed.
        XCTAssertFalse(answer.localizedCaseInsensitiveContains("cancelled"),
                       "Accepted confirmation must not report cancellation, got: \(answer)")
    }

    // MARK: - 7. Unknown/conversational requests still reach the model

    func testUnknownRequestStillUsesModel() async {
        let provider = MockAIProvider(response: #"{"type":"final_answer","answer":"Recursion is when a function calls itself."}"#)
        let assistant = AssistantManager(provider: provider)
        let answer = await assistant.submit("explain recursion", settings: settings())
        XCTAssertEqual(answer, "Recursion is when a function calls itself.",
                       "Open-ended requests must fall through to the model loop")
    }
}
