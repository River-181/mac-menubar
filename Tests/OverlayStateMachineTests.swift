import XCTest
@testable import NotchDock

final class OverlayStateMachineTests: XCTestCase {
    func testClickFlow() {
        let machine = OverlayStateMachine()
        var state: OverlayState = .hidden

        state = machine.reduce(state: state, event: .pointerEnterTrigger, isDragging: false)
        XCTAssertEqual(state, .peek)

        state = machine.reduce(state: state, event: .clickCapsule, isDragging: false)
        XCTAssertEqual(state, .expand)

        state = machine.reduce(state: state, event: .esc, isDragging: false)
        XCTAssertEqual(state, .peek)

        state = machine.reduce(state: state, event: .esc, isDragging: false)
        XCTAssertEqual(state, .hidden)
    }

    func testDragForcesExpand() {
        let machine = OverlayStateMachine()
        var state: OverlayState = .hidden
        state = machine.reduce(state: state, event: .dragBegan, isDragging: true)
        XCTAssertEqual(state, .expand)
    }

    func testDropCommitAndFinishFlow() {
        let machine = OverlayStateMachine()
        var state: OverlayState = .expand
        state = machine.reduce(state: state, event: .dropCommitted, isDragging: true)
        XCTAssertEqual(state, .processing)
        state = machine.reduce(state: state, event: .dragEnded, isDragging: false)
        XCTAssertEqual(state, .peek)
    }

    func testTriggerEngineHysteresis() {
        let trigger = TriggerEngine(enterDelay: 0.035, exitDelay: 0.1)
        XCTAssertNil(trigger.update(rawInside: true, timestamp: 0))
        XCTAssertEqual(trigger.state, .entering)
        XCTAssertNil(trigger.update(rawInside: true, timestamp: 0.02))
        XCTAssertEqual(trigger.state, .entering)
        XCTAssertEqual(trigger.update(rawInside: true, timestamp: 0.04), .pointerEnterTrigger)
        XCTAssertEqual(trigger.state, .inside)
        XCTAssertNil(trigger.update(rawInside: false, timestamp: 0.05))
        XCTAssertEqual(trigger.state, .exiting)
        XCTAssertNil(trigger.update(rawInside: false, timestamp: 0.10))
        XCTAssertEqual(trigger.update(rawInside: false, timestamp: 0.16), .pointerExitTrigger)
        XCTAssertEqual(trigger.state, .outside)
    }
}
