import XCTest

@testable import leqraCore

final class LocalInputSourcesTests: XCTestCase {
    func testFireDragAimsInPlaceWithoutChangingOtherHeldSources() {
        var sources = LocalInputSources()
        sources.touch = GameInput(fire: true, stickX: 1)
        sources.keyboard.forward = true
        sources.fireAim = BeamPoint(x: 0, y: -1)
        let aimed = sources.input
        XCTAssertTrue(aimed.fire)
        XCTAssertTrue(aimed.aimOnly)
        XCTAssertTrue(aimed.snapAim)
        XCTAssertEqual(aimed.stickX, 0)
        XCTAssertEqual(aimed.stickY, -1)
        sources.fireAim = nil
        XCTAssertEqual(sources.input.stickX, 1)
        XCTAssertTrue(sources.input.forward)
        sources.fireAim = BeamPoint(x: 1, y: 0)
        sources.reset()
        XCTAssertNil(sources.fireAim)
    }
    func testKeyboardAndMouseCombineWithoutMovingTheTouchSeat() {
        let p1 = LocalInputSources()
        var p2 = LocalInputSources()
        p2.keyboard.forward = true
        p2.mouseAim = BeamPoint(x: 0, y: -1)
        p2.mouseFire = true
        XCTAssertFalse(p1.input.forward)
        XCTAssertFalse(p1.input.fire)
        XCTAssertTrue(p2.input.forward)
        XCTAssertTrue(p2.input.fire)
        XCTAssertTrue(p2.input.aimOnly)
        XCTAssertFalse(p2.input.snapAim)
        XCTAssertEqual(p2.input.stickY, -1)
        p2.keyboard.left = true
        XCTAssertFalse(p2.input.aimOnly, "Manual turret rotation temporarily overrides the pointer")
        p2.keyboard.left = false
        p2.mouseFire = false
        XCTAssertTrue(p2.input.forward)
    }
    func testTouchAndGamepadSourcesReleaseIndependently() {
        var sources = LocalInputSources()
        sources.keyboard.fire = true
        sources.touch.fire = true
        sources.gamepad.forward = true
        sources.touch.stickX = 1
        sources.touch.touchAim = true
        sources.touch.fire = false
        XCTAssertTrue(sources.input.fire)
        XCTAssertTrue(sources.input.forward)
        XCTAssertEqual(sources.input.stickX, 1)
        sources.touch = GameInput()
        sources.keyboard.fire = false
        XCTAssertFalse(sources.input.fire)
        XCTAssertTrue(sources.input.forward)
        sources.gamepad.stickY = -1
        XCTAssertEqual(sources.input.stickY, -1)
        sources.reset()
        XCTAssertEqual(sources.input, GameInput())
    }
    func testEveryFireSourceCanHoldThroughOtherSourceRelease() {
        let all: [FireInputSources.Source] = [.touch, .keyboard, .mouse, .gamepad]
        for first in all {
            for second in all where first != second {
                var sources = FireInputSources()
                sources.set(first, down: true)
                sources.set(second, down: true)
                sources.set(first, down: false)
                XCTAssertTrue(sources.held)
                sources.set(second, down: false)
                XCTAssertFalse(sources.held)
            }
        }
    }
}
