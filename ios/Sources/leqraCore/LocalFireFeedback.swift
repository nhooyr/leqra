import Foundation

/// A local input cue, independent of ammunition, projectiles and simulation.
public struct LocalFireFeedback {
    private struct Identity: Equatable {
        var id: Int
        var spawn: Int
        var generation: Int
    }
    private var identity: Identity?
    private var held = false
    private var lastPress = -Double.infinity
    private var until = -Double.infinity

    public init() {}
    public mutating func reset() {
        identity = nil
        held = false
        lastPress = -.infinity
        until = -.infinity
    }

    /// Use current authoritative magazine counts, without aging shots out of
    /// their quota or counting projectiles retained for visual presentation.
    public static func ammoUnavailable(for tank: ArenaTank, stateAge: Double = 0) -> Bool {
        guard stateAge.isFinite, tank.starmanTime <= max(0, stateAge) else { return false }
        let used = max(0, tank.ammoUsed)
        switch tank.power {
        case "rapid": return tank.machineRounds <= 0 || used >= 115
        case "scatter": return tank.charges <= 0 || used > 9
        case "laser": return tank.charges <= 0
        case "homing", "grenade", "cannon": return tank.charges <= 0 || used >= 3
        default: return used >= 5
        }
    }

    private mutating func reconcile(tank: ArenaTank?, generation: Int, active: Bool) {
        let next = tank.map { Identity(id: $0.id, spawn: $0.spawnSerial, generation: generation) }
        if identity != next || !active || (tank?.hp ?? 0) <= 0 {
            lastPress = -.infinity
            until = -.infinity
        }
        identity = next
    }

    @discardableResult public mutating func setFire(
        _ down: Bool, tank: ArenaTank?, generation: Int,
        now: Double, stateAge: Double = 0, active: Bool = true, muzzleBlocked: Bool = false
    ) -> Bool {
        let pressed = down && !held
        held = down  // This fresh-press cosmetic cue never gates held simulation input.
        reconcile(tank: tank, generation: generation, active: active)
        guard pressed, active, now.isFinite, stateAge.isFinite, let tank, tank.hp > 0 else { return false }
        let age = max(0, stateAge)
        let boosted = tank.starmanTime > age
        guard !(tank.spawnProtected && tank.invulnerable > age), boosted || tank.cooldown <= age,
            tank.power != "grenade", tank.grenades == 0, !muzzleBlocked
        else { return false }
        let cadence: Double
        if boosted {
            cadence = 0.065
        } else {
            switch tank.power {
            case "": cadence = 0.34
            case "scatter": cadence = 0.27
            case "homing": cadence = 0.36
            case "laser", "cannon": cadence = 0.85 / 3
            default: cadence = 0.15  // Rapid's zero cooldown uses the web press-feedback fallback.
            }
        }
        guard now - lastPress + 1e-12 >= cadence else { return false }
        lastPress = now
        until = now + 0.1
        return true
    }

    public mutating func recoil(
        real: Double, tank: ArenaTank?, generation: Int, now: Double, active: Bool = true
    ) -> Double {
        reconcile(tank: tank, generation: generation, active: active)
        guard now.isFinite else { return real }
        return max(real, min(1, max(0, (until - now) / 0.1)))
    }
}
