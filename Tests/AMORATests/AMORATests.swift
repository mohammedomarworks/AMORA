import XCTest
@testable import AMORA

final class AMORATests: XCTestCase {
    func testExpressionInit() {
        let expr = Expression.neutral
        XCTAssertEqual(expr.eyes, .normal)
        XCTAssertEqual(expr.mouth, .neutral)
    }

    func testStatePriority() {
        XCTAssertTrue(AMORAState.error.priority > AMORAState.idle.priority)
        XCTAssertTrue(AMORAState.expanded.priority > AMORAState.idle.priority)
    }

    func testRobotInit() {
        let robot = AMORARobot()
        XCTAssertEqual(robot.state, .idle)
    }
}
