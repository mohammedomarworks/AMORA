import XCTest
@testable import AMORA

@MainActor
final class AMORATests: XCTestCase {
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
}
