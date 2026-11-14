import Foundation

/// Pre-contact visual state. Authority still owns all damage and scoring.
public struct ImpactContactPose: Codable, Equatable, Sendable {
    public var x: Double, y: Double, angle: Double, vx: Double, vy: Double
    public var hp: Int
    public var shield: Double
    public var shieldCharges: Int
    public var invulnerable: Double
    public var spawnProtected: Bool

    public init(_ tank: ArenaTank) {
        x = tank.x; y = tank.y; angle = tank.angle; vx = tank.vx; vy = tank.vy
        hp = tank.hp; shield = tank.shield; shieldCharges = tank.shieldCharges
        invulnerable = tank.invulnerable; spawnProtected = tank.spawnProtected
    }

    var valid: Bool {
        [x, y, angle, vx, vy, shield, invulnerable].allSatisfy(\.isFinite)
            && abs(x) <= 1e12 && abs(y) <= 1e12 && hp > 0 && shield >= 0
            && shieldCharges >= 0 && shieldCharges <= 5 && invulnerable >= 0
    }

    func applying(to source: ArenaTank) -> ArenaTank {
        var value = source
        value.x = x; value.y = y; value.angle = angle; value.vx = vx; value.vy = vy
        value.hp = hp; value.shield = shield; value.shieldCharges = shieldCharges
        value.invulnerable = invulnerable; value.spawnProtected = spawnProtected
        return value
    }
}

public struct ImpactContact: Codable, Equatable, Sendable {
    public var projectileId: Int
    public var kind: String
    public var tick: Double
    public var target: Int
    public var spawnSerial: Int
    public var before: ImpactContactPose

    public init(projectileId: Int, kind: String, tick: Double, target: Int, spawnSerial: Int, before: ImpactContactPose) {
        self.projectileId = projectileId; self.kind = kind; self.tick = tick
        self.target = target; self.spawnSerial = spawnSerial; self.before = before
    }

    var valid: Bool {
        projectileId >= 0 && target >= 0 && spawnSerial >= 0 && tick.isFinite && tick >= 0 && before.valid
            && ["regular", "rapid", "scatter", "homing", "grenade", "cannon", "laser", "starman"].contains(kind)
    }
}
