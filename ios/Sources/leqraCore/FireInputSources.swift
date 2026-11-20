import Foundation

/// Touch and hardware Fire are independent sources for one local controller.
/// Releasing one source must not invent a release while the other is held.
public struct FireInputSources: Sendable {
    public enum Source { case touch, keyboard, mouse, gamepad }
    private var touch = false
    private var keyboard = false
    private var mouse = false
    private var gamepad = false
    public var held: Bool { touch || keyboard || mouse || gamepad }
    public init() {}
    @discardableResult public mutating func set(_ source: Source, down: Bool) -> Bool {
        switch source {
        case .touch: touch = down
        case .keyboard: keyboard = down
        case .mouse: mouse = down
        case .gamepad: gamepad = down
        }
        return held
    }
    public mutating func reset() {
        touch = false
        keyboard = false
        mouse = false
        gamepad = false
    }
}

/// Each physical source retains its own held state. Releasing one device cannot
/// cancel another device's movement, aiming, or fire for the same local pilot.
public struct LocalInputSources: Sendable {
    public var touch = GameInput()
    public var keyboard = GameInput()
    public var gamepad = GameInput()
    public var mouseAim: BeamPoint?
    public var mouseFire = false
    public init() {}

    public var input: GameInput {
        var result = GameInput(
            forward: keyboard.forward || gamepad.forward,
            reverse: keyboard.reverse || gamepad.reverse,
            left: keyboard.left || gamepad.left,
            right: keyboard.right || gamepad.right,
            fire: touch.fire || keyboard.fire || gamepad.fire || mouseFire
        )
        let touchActive = hypot(touch.stickX, touch.stickY) > 0.1
        let gamepadActive = hypot(gamepad.stickX, gamepad.stickY) > 0.1
        let aim: GameInput?
        if touchActive {
            aim = touch
        } else if gamepadActive {
            aim = gamepad
        } else if let mouseAim, !result.left, !result.right {
            aim = GameInput(stickX: mouseAim.x, stickY: mouseAim.y, touchAim: false, aimOnly: true)
        } else {
            aim = nil
        }
        if let aim {
            result.stickX = aim.stickX
            result.stickY = aim.stickY
            result.touchAim = aim.touchAim
            result.aimOnly = aim.aimOnly
            result.snapAim = aim.snapAim
        }
        return result
    }

    public mutating func reset() { self = LocalInputSources() }
}
