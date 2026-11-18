import Foundation

public enum NativeGamepadControls {
    /// Stick axes use game coordinates, with positive Y pointing down.
    public static func input(leftX: Double, leftY: Double, rightX: Double, rightY: Double,
                             forward: Bool, reverse: Bool, left: Bool, right: Bool, fire: Bool) -> GameInput {
        let driving = hypot(leftX, leftY) >= 0.15
        let aiming = hypot(rightX, rightY) >= 0.15
        guard driving || aiming || forward || reverse || left || right || fire else { return GameInput() }
        let drive = driving ? (leftX, leftY) : (0, 0)
        let (x, y) = aiming ? (rightX, rightY) : drive
        return GameInput(
            forward: forward || (aiming && driving && !reverse), reverse: reverse,
            left: left, right: right, fire: fire,
            stickX: x, stickY: y, touchAim: false, aimOnly: aiming
        )
    }

    public static func seat(for controllerSeat: Int, connected: Int, primary: Bool, secondary: Bool) -> Int? {
        guard (0..<2).contains(controllerSeat), connected > 0 else { return nil }
        switch (primary, secondary) {
        case (true, true): return controllerSeat
        case (true, false): return connected == 1 || controllerSeat == 0 ? 0 : nil
        case (false, true): return connected == 1 || controllerSeat == 1 ? 1 : nil
        case (false, false): return nil
        }
    }
}
