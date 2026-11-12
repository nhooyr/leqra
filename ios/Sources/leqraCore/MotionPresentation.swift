import Foundation

/// Keeps local display motion continuous when controls change between physics
/// ticks. Its bounded offsets never change simulation, inputs, hits, or score.
public final class TankMotionPresenter {
    private struct State {
        var source: ArenaTank
        var previous: ArenaTank?
        var input: GameInput
        var tick: UInt64
        var generation: Int
        var fraction: Double
        var x = 0.0
        var y = 0.0
        var angle = 0.0
    }
    private var state: State?

    public init() {}

    public func reset() { state = nil }

    /// Reconciliation already has its own visual correction. Rebase the
    /// forecast history so a control change cannot count that correction twice.
    public func rebase(dx: Double, dy: Double, angle: Double) {
        guard var value = state else { return }
        value.source.x += dx; value.source.y += dy; value.source.angle += angle
        if var previous = value.previous {
            previous.x += dx; previous.y += dy; previous.angle += angle
            value.previous = previous
        }
        state = value
    }

    public func present(tank: ArenaTank, input: GameInput, tick: UInt64, generation: Int = 0,
                        fraction: Double, move: (inout ArenaTank, GameInput, Double) -> Void,
                        canInterpolate: (ArenaTank, ArenaTank) -> Bool = { _, _ in true }) -> ArenaTank {
        guard fraction.isFinite, fraction >= 0, tank.hp > 0 else { reset(); return tank }
        let fraction = min(1, fraction)
        var preceding: ArenaTank?
        if let old = state, generation == old.generation,
           tank.spawnSerial == old.source.spawnSerial, tank.hp == old.source.hp {
            if tick == old.tick { preceding = old.previous }
            else if tick == old.tick + 1 { preceding = old.source }
        }
        let raw = TankMovement.presentation(tank: tank, input: input, fraction: fraction,
            previous: preceding, move: move, canInterpolate: canInterpolate)
        var controls = input
        controls.seq = 0; controls.fire = false
        var next = State(source: tank, previous: preceding, input: controls, tick: tick,
                         generation: generation, fraction: fraction)
        if let previous = state {
            let ticks = Double(tick) - Double(previous.tick)
            let elapsed = (ticks + fraction - previous.fraction) / 60
            let sameLife = generation == previous.generation
                && tank.spawnSerial == previous.source.spawnSerial && tank.hp == previous.source.hp
                && (tank.ghostTime > 0) == (previous.source.ghostTime > 0)
                && (raw.ghostTime > 0) == (tank.ghostTime > 0)
            if sameLife, elapsed >= 0, elapsed <= 0.1, ticks >= 0, ticks <= 6 {
                let fade = exp(-elapsed / 0.04)
                next.x = previous.x * fade; next.y = previous.y * fade; next.angle = previous.angle * fade
                if ticks > 0 || controls != previous.input {
                    // Compare the old input at this same display time. Using
                    // the previous rendered pose would discard elapsed motion
                    // whenever an analog stick changes on every display tick.
                    var expected = previous.source
                    var expectedPreceding = previous.previous
                    for _ in 0..<Int(ticks) {
                        expectedPreceding = expected
                        move(&expected, previous.input, 1 / 60)
                    }
                    if hypot(expected.x - tank.x, expected.y - tank.y) <= 42 {
                        expected = TankMovement.presentation(tank: expected, input: previous.input,
                            fraction: fraction, previous: expectedPreceding, move: move, canInterpolate: canInterpolate)
                        next.x += expected.x - raw.x; next.y += expected.y - raw.y
                        next.angle += atan2(sin(expected.angle - raw.angle), cos(expected.angle - raw.angle))
                    } else {
                        next.x = 0; next.y = 0; next.angle = 0
                    }
                }
                let limit = 128.0 * (1 + 0.65 * 5) / 60, length = hypot(next.x, next.y)
                if length > limit { next.x *= limit / length; next.y *= limit / length }
                next.angle = min(0.3375, max(-0.3375, next.angle))
            }
        }
        var result = raw
        result.x += next.x; result.y += next.y; result.angle += next.angle
        if !canInterpolate(tank, result) {
            next.x = 0; next.y = 0; next.angle = 0
            result = raw
        }
        state = next
        return result
    }
}
