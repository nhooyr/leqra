import XCTest

@testable import leqraCore

final class NativeGamepadControlsTests: XCTestCase {
    func testRadialDeadZonesAndLeftStickDrive() {
        XCTAssertEqual(input(leftX: 0.1, leftY: 0.1, rightX: -0.1, rightY: 0.1), GameInput())
        let drive = input(leftX: 0.12, leftY: -0.12, rightX: 0.07, rightY: -0.07)
        XCTAssertEqual(drive.stickX, 0.12)
        XCTAssertEqual(drive.stickY, -0.12)
        XCTAssertFalse(drive.aimOnly)
        XCTAssertFalse(drive.touchAim)
        XCTAssertGreaterThan(TankMovement.steer(angle: -.pi / 4, input: drive, dt: 0.01).throttle, 0)
    }

    func testRightStickAimsWithLeftStickThrottleOrExplicitReverse() {
        let stationary = input(rightX: 0.12, rightY: 0.12, fire: true)
        XCTAssertTrue(stationary.aimOnly)
        XCTAssertTrue(stationary.fire)
        XCTAssertEqual(TankMovement.steer(angle: 0, input: stationary, dt: 0.01).throttle, 0)
        let moving = input(leftX: 0.5, rightX: 0.12, rightY: 0.12)
        XCTAssertEqual(moving.stickX, stationary.stickX)
        XCTAssertEqual(moving.stickY, stationary.stickY)
        XCTAssertEqual(TankMovement.steer(angle: 0, input: moving, dt: 0.01).throttle, 1)
        let backingUp = input(leftX: 0.5, rightX: 0.5, reverse: true)
        XCTAssertEqual(TankMovement.steer(angle: 0, input: backingUp, dt: 0.01).throttle, -0.72)
    }

    func testDigitalControlsAndLogicalFireRemainAvailable() {
        let digital = NativeGamepadControls.input(
            leftX: 0, leftY: 0, rightX: 0, rightY: 0,
            forward: true, reverse: false, left: true, right: false, fire: true)
        XCTAssertEqual(digital, GameInput(forward: true, left: true, fire: true, touchAim: false))
        XCTAssertEqual(input(), GameInput())
    }

    func testControllerSeatsStayFixedWhenPairedAndOnlyAControllerAloneCanFollowASolePilot() {
        let seat = NativeGamepadControls.seat
        XCTAssertEqual(seat(0, 2, true, true), 0)
        XCTAssertEqual(seat(1, 1, true, true), 1)
        XCTAssertNil(seat(2, 3, true, true))
        XCTAssertEqual(seat(1, 1, true, false), 0)
        XCTAssertEqual(seat(0, 1, false, true), 1)
        XCTAssertEqual(seat(0, 2, true, false), 0)
        XCTAssertEqual(seat(1, 2, false, true), 1)
        XCTAssertNil(seat(1, 2, true, false))
        XCTAssertNil(seat(0, 2, false, true))
        XCTAssertNil(seat(0, 0, true, true))
        XCTAssertNil(seat(0, 1, false, false))
    }

    private func input(
        leftX: Double = 0, leftY: Double = 0, rightX: Double = 0, rightY: Double = 0,
        reverse: Bool = false, fire: Bool = false
    ) -> GameInput {
        NativeGamepadControls.input(
            leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY,
            forward: false, reverse: reverse, left: false, right: false, fire: fire)
    }
}
