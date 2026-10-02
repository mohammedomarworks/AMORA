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
}
