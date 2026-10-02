import XCTest
@testable import AMORA

@MainActor
final class AMORATests: XCTestCase {
    struct SlowProvider: AIProvider {
        let kind: AIProviderKind = .local
        var isAvailable: Bool { true }
        func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
            try await Task.sleep(for: .seconds(10))
            return "late"
        }
    }
    func testExpressionInit() {
        let expr = Expression.neutral
        XCTAssertEqual(expr.eyes, .normal)
        XCTAssertEqual(expr.mouth, .neutral)
    }

    func testStatePriority() {
        XCTAssertTrue(AMORAState.error.priority > AMORAState.idle.priority)
        XCTAssertTrue(AMORAState.expanded.priority > AMORAState.idle.priority)
        XCTAssertTrue(AMORAState.alert.priority > AMORAState.music.priority)
    }

    func testRobotInit() {
        let robot = AMORARobot()
        XCTAssertEqual(robot.state, .idle)
    }

    func testContextRecordsMeaningfulEventsWithoutUserContent() {
        let context = AMORAContext.shared
        context.record(.noteCreated)
        XCTAssertEqual(context.lastAction, "note")
        XCTAssertEqual(context.currentEvent, .noteCreated)
        XCTAssertNil(context.lastAction?.contains("buy") == true ? context.lastAction : nil)
    }

    func testEventCenterRoutesToContext() {
        let context = AMORAContext.shared
        AMORAEventCenter.shared.emit(.fileReceived)
        XCTAssertEqual(context.lastAction, "file")
        XCTAssertEqual(context.currentEvent, .fileReceived)
    }

    func testNaturalTimerParsing() {
        let parser = AMORACommandParser()
        let inputs = [
            ("timer 25", 25 * 60),
            ("start timer 25", 25 * 60),
            ("start a 25 minute timer", 25 * 60),
            ("start a 25 min timer", 25 * 60),
            ("give me a 25 min focus session", 25 * 60),
            ("set a timer for 10 minutes", 10 * 60),
            ("set timer for 1 hour", 60 * 60)
        ]
        for (input, seconds) in inputs {
            XCTAssertEqual(parser.parse(input), .startTimer(duration: TimeInterval(seconds)), input)
        }
        XCTAssertEqual(parser.parse("start timer"), .unknown(text: "start timer"))
    }

    func testNaturalModuleParsing() {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("play"), .playMusic)
        XCTAssertEqual(parser.parse("pause music"), .pauseMusic)
        XCTAssertEqual(parser.parse("next song"), .nextTrack)
        XCTAssertEqual(parser.parse("previous track"), .previousTrack)
        XCTAssertEqual(parser.parse("what's my battery"), .showBattery)
        XCTAssertEqual(parser.parse("how much battery do I have"), .showBattery)
        XCTAssertEqual(parser.parse("show clipboard"), .showClipboard)
        XCTAssertEqual(parser.parse("show notes"), .showNotes)
        XCTAssertEqual(parser.parse("open dashboard"), .showDashboard)
        XCTAssertEqual(parser.parse("settings"), .showSettings)
        XCTAssertEqual(parser.parse("open Downloads"), .openFolder(name: "downloads"))
        XCTAssertEqual(parser.parse("open VS Code"), .openApplication(name: "vs code"))
    }

    func testNoteExtractionAndSafeUnknowns() {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("add a note buy milk"), .createNote(text: "buy milk"))
        XCTAssertEqual(parser.parse("save a note that says finish Java assignment"), .createNote(text: "finish Java assignment"))
        XCTAssertEqual(parser.parse("make a note saying call dad"), .createNote(text: "call dad"))
        XCTAssertEqual(parser.parse("make me a website"), .unknown(text: "make me a website"))
        XCTAssertEqual(parser.parse("tell me a joke"), .unknown(text: "tell me a joke"))
        XCTAssertEqual(parser.parse("what is the weather"), .unknown(text: "what is the weather"))
    }

    func testFollowUpContext() {
        let parser = AMORACommandParser()
        let timerContext = AMORACommandContext(activeTimer: true)
        XCTAssertEqual(parser.parse("pause it", context: timerContext), .pauseTimer)
        XCTAssertEqual(parser.parse("resume it", context: timerContext), .resumeTimer)
        let musicContext = AMORACommandContext(activeMedia: true)
        XCTAssertEqual(parser.parse("pause it", context: musicContext), .pauseMusic)
    }

    func testRouterDoesNotGuessMissingDuration() {
        let result = AMORACommandRouter.shared.execute(.unknown(text: "start timer"))
        XCTAssertEqual(result, .needsInformation(prompt: "How long should I set it for?"))
    }

    func testLocalFirstRoutingDistinguishesBatteryAdvice() async {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("battery"), .showBattery)
        XCTAssertEqual(parser.parse("what's my battery?"), .showBattery)
        XCTAssertEqual(parser.parse("how can I improve my battery life?"), .unknown(text: "how can i improve my battery life"))
        XCTAssertEqual(parser.parse("start a timer for 25 minutes"), .startTimer(duration: 1_500))
        XCTAssertEqual(parser.parse("help me plan a 25 minute study session"), .unknown(text: "help me plan a 25 minute study session"))
    }

    func testAssistantUsesMockProviderAndConversationIsBounded() async {
        let manager = AssistantManager(provider: MockAIProvider(response: "A mock answer."))
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)
        let answer = await manager.submit("explain recursion", settings: settings)
        XCTAssertEqual(answer, "A mock answer.")
        XCTAssertEqual(manager.conversation.messages.count, 2)
        XCTAssertEqual(manager.state, .responding)
    }

    func testDisabledAssistantFallsBackWithoutCallingProvider() async {
        let manager = AssistantManager(provider: MockAIProvider(response: "must not be used"))
        let settings = AISettingsSnapshot(enabled: false, provider: .local, model: "mock", apiKey: nil)
        let answer = await manager.submit("tell me something", settings: settings)
        XCTAssertEqual(answer, "AI Assistant is turned off in Settings.")
        XCTAssertEqual(manager.lastError, .unavailable)
        XCTAssertTrue(manager.conversation.messages.isEmpty)
    }

    func testToolValidationIsAllowlistedAndConfirmationAware() {
        let validator = AMORAToolValidator()
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .battery, operation: .readBattery)), .allowed)
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .timer, operation: .startTimer(seconds: 90_000))), .rejected(reason: "Timer duration is outside the supported range."))
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .file, operation: .openFolder(name: "Downloads"))), .needsConfirmation(prompt: "Would you like me to open Downloads?"))
    }

    func testAssistantCancellationReturnsSafely() async {
        let manager = AssistantManager(provider: SlowProvider())
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "slow", apiKey: nil)
        let request = Task { await manager.submit("explain recursion", settings: settings) }
        try? await Task.sleep(for: .milliseconds(20))
        manager.cancel()
        let answer = await request.value
        XCTAssertEqual(answer, "Okay — stopped.")
        XCTAssertEqual(manager.state, .cancelled)
    }

    func testProviderFactorySelectsAppleOnDeviceWithoutAnAPIKey() {
        let settings = AISettingsSnapshot(enabled: true, provider: .appleOnDevice, model: "apple-on-device", apiKey: nil)
        let provider = AIProviderFactory.make(for: settings)
        XCTAssertEqual(provider.kind, .appleOnDevice)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(provider is AppleFoundationModelProvider)
        }
    }

    func testCloudProviderWithoutKeyReportsAuthenticationRequirement() async {
        let manager = AssistantManager(provider: MockAIProvider(response: "must not be used"), providerIsInjected: false)
        let settings = AISettingsSnapshot(enabled: true, provider: .openAI, model: "gpt", apiKey: nil)
        let answer = await manager.submit("tell me a joke", settings: settings)
        XCTAssertEqual(answer, "Your AI provider needs a valid API key.")
        XCTAssertEqual(manager.lastError, .authenticationRequired)
    }

    func testConversationContextIsPassedToProvider() async {
        let provider = MockAIProvider(response: "A follow-up answer.")
        let manager = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)
        _ = await manager.submit("what is recursion?", settings: settings)
        _ = await manager.submit("show me an example", settings: settings)
        XCTAssertEqual(manager.conversation.messages.count, 4)
        XCTAssertEqual(manager.conversation.messages[2].content, "show me an example")
    }
}
