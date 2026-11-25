import XCTest

@testable import leqraCore

final class LocalInputSourcesTests: XCTestCase {
    func testFireDragAimsInPlaceWithoutChangingOtherHeldSources() {
        var sources = LocalInputSources()
        sources.touch = GameInput(fire: true)
        sources.keyboard.forward = true
        sources.fireAim = BeamPoint(x: 0, y: -1)
        let aimed = sources.input
        XCTAssertTrue(aimed.fire)
        XCTAssertEqual(aimed.aimX, 0)
        XCTAssertEqual(aimed.aimY, -1)
        XCTAssertEqual(aimed.stickX, 0)
        XCTAssertEqual(aimed.stickY, 0)
        sources.touch.stickX = 1
        sources.fireAim = nil
        XCTAssertEqual(sources.input.stickX, 1)
        XCTAssertTrue(sources.input.forward)
        sources.fireAim = BeamPoint(x: 1, y: 0)
        sources.reset()
        XCTAssertNil(sources.fireAim)
    }
    func testJoystickKeepsMovingWhileFireChangesAim() {
        var sources = LocalInputSources()
        sources.touch = GameInput(stickX: 0.6)
        sources.fireAim = BeamPoint(x: 0, y: -1)
        let aimed = sources.input
        XCTAssertFalse(aimed.aimOnly)
        XCTAssertFalse(aimed.snapAim)
        XCTAssertEqual(aimed.stickX, 0.6)
        XCTAssertEqual(aimed.stickY, 0)
        XCTAssertEqual(aimed.aimX, 0)
        XCTAssertEqual(aimed.aimY, -1)
        var tank = ArenaTank(x: 200, y: 200)
        for _ in 0..<30 {
            TankMovement.step(tank: &tank, input: aimed, dt: 1 / 60, walls: [], width: 1000, height: 1000)
        }
        XCTAssertEqual(tank.x, 238.4, accuracy: 0.0001)
        XCTAssertEqual(tank.y, 200, accuracy: 0.0001)
        XCTAssertEqual(tank.movementAngle, 0, accuracy: 0.0001)
        XCTAssertEqual(tank.angle, -.pi / 2, accuracy: 0.0001)
        sources.touch = GameInput()
        XCTAssertEqual(sources.input.aimY, -1)
        XCTAssertEqual(sources.input.stickX, 0)
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
        XCTAssertFalse(p2.input.aimOnly)
        XCTAssertFalse(p2.input.snapAim)
        XCTAssertEqual(p2.input.stickY, 0)
        XCTAssertEqual(p2.input.aimY, -1)
        p2.keyboard.left = true
        XCTAssertTrue(p2.input.left)
        XCTAssertEqual(p2.input.aimY, -1, "Keyboard steering leaves the turret on its pointer target")
        p2.keyboard.left = false
        p2.mouseFire = false
        XCTAssertTrue(p2.input.forward)
    }

    func testMouseAimKeepsKeyboardHullMovementAndTurningIndependent() {
        let world = ArenaWorld(width: 1000, height: 1000)
        for fixed in [false, true] {
            for keyboard in [GameInput(forward: true, left: true), GameInput(reverse: true, right: true)] {
                var sources = LocalInputSources()
                sources.keyboard = keyboard
                sources.mouseAim = BeamPoint(x: 0, y: -1)
                var aimed = ArenaTank(id: 1, x: 420, y: 420, angle: 0.5, ghostTime: 10)
                var keyboardOnly = aimed
                let maze = fixed ? InfiniteMaze(world: world) : InfiniteMaze(seed: 42)
                for _ in 0..<30 {
                    TankMovement.step(tank: &aimed, input: sources.input, dt: 1 / 60, maze: maze)
                    TankMovement.step(tank: &keyboardOnly, input: keyboard, dt: 1 / 60, maze: maze)
                    XCTAssertEqual(aimed.x, keyboardOnly.x, accuracy: 1e-10)
                    XCTAssertEqual(aimed.y, keyboardOnly.y, accuracy: 1e-10)
                    XCTAssertEqual(aimed.movementAngle, keyboardOnly.movementAngle, accuracy: 1e-10)
                    XCTAssertEqual(aimed.angle, -.pi / 2, accuracy: 1e-10)
                    XCTAssertTrue(aimed.independentAim)
                }
                sources.mouseAim = nil
                XCTAssertEqual(
                    sources.input, keyboard, "Leaving pointer aim restores the same keyboard controls")
            }
        }
    }

    func testMouseAimsAndFiresWithoutRotatingTheStationaryHull() throws {
        let world = ArenaWorld(width: 1000, height: 1000)
        let game = PracticeArena(seed: 42, name: "Pilot", colorIndex: 0, botCount: 0, world: world)
        game.snapshot.tanks = [ArenaTank(id: 1, x: 420, y: 420, angle: 0.5)]
        var sources = LocalInputSources()
        sources.mouseAim = BeamPoint(x: 0, y: -1)
        sources.mouseFire = true
        game.step(input: sources.input, dt: 1 / 60)
        let tank = try XCTUnwrap(game.snapshot.tanks.first)
        XCTAssertEqual(tank.x, 420)
        XCTAssertEqual(tank.y, 420)
        XCTAssertEqual(tank.movementAngle, 0.5, accuracy: 1e-10)
        XCTAssertEqual(tank.angle, -.pi / 2, accuracy: 1e-10)
        let shot = try XCTUnwrap(game.snapshot.bullets.first)
        XCTAssertEqual(shot.vx, 0, accuracy: 1e-10)
        XCTAssertLessThan(shot.vy, 0)
    }

    func testTouchAndGamepadSteeringKeepPriorityOverHardwarePointer() {
        var sources = LocalInputSources()
        sources.mouseAim = BeamPoint(x: 0, y: -1)
        sources.touch = GameInput(stickX: 0.6)
        XCTAssertEqual(sources.input.stickX, 0.6)
        XCTAssertEqual(sources.input.aimY, 0)
        sources.touch = GameInput()
        sources.gamepad = GameInput(stickX: -0.7)
        XCTAssertEqual(sources.input.stickX, -0.7)
        XCTAssertEqual(sources.input.aimY, 0)
        sources.gamepad = GameInput(left: true)
        XCTAssertTrue(sources.input.left)
        XCTAssertEqual(sources.input.aimY, 0)
        sources.gamepad = GameInput()
        sources.fireAim = BeamPoint(x: 1, y: 0)
        XCTAssertEqual(sources.input.aimX, 1)
        XCTAssertEqual(sources.input.aimY, 0)
    }

    func testFreshPointerEventResumesAimAfterTouchFireEnds() {
        var sources = LocalInputSources()
        sources.mouseAim = BeamPoint(x: 0, y: -1)
        sources.fireAim = BeamPoint(x: 1, y: 0)
        sources.touch.fire = true
        XCTAssertFalse(sources.resumeMouseAim())
        XCTAssertEqual(sources.input.aimX, 1, "Active touch Fire keeps its aim")
        sources.touch.fire = false
        XCTAssertEqual(sources.input.aimX, 1, "Touch aim remains until another input claims it")
        XCTAssertTrue(sources.resumeMouseAim())
        XCTAssertEqual(sources.input.aimX, 0)
        XCTAssertEqual(sources.input.aimY, -1)
        XCTAssertFalse(sources.resumeMouseAim())
    }

    func testFreshPointerEventResumesAimAfterDirectTouchEnds() {
        var sources = LocalInputSources()
        sources.mouseAim = BeamPoint(x: 0, y: -1)
        sources.touch = GameInput(stickX: 1, aimOnly: true, snapAim: true)
        XCTAssertFalse(sources.resumeMouseAim(directTouchActive: true))
        XCTAssertEqual(sources.input.stickX, 1, "An active direct-touch gesture keeps its aim")
        sources.touch.fire = true
        XCTAssertFalse(sources.resumeMouseAim(directTouchActive: false))
        sources.touch.fire = false
        XCTAssertTrue(sources.resumeMouseAim(directTouchActive: false))
        XCTAssertEqual(sources.input.stickX, 0)
        XCTAssertEqual(sources.input.aimY, -1)
        XCTAssertFalse(sources.input.snapAim)
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
