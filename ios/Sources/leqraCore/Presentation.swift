import Foundation

public extension ArenaTank {
    /// Trust the actual tier in the snapshot, never the editable callsign.
    var botWarning: String? { bot && difficulty == "godlike" ? "GODLIKE" : nil }
}

public extension ArenaSnapshot {
    /// Fixed-match winners identify a tank; every member of its positive team
    /// shares that win. Missing pilots and draws have no local result.
    func isWinningSide(localID: Int) -> Bool? {
        guard winner >= 0,
              let local = tanks.first(where: { $0.id == localID }),
              let winningTank = tanks.first(where: { $0.id == winner }) else { return nil }
        return winner == localID || local.team > 0 && local.team == winningTank.team
    }
}

/// Text and progress values shared by both native arena layouts. Equipment and
/// readiness are separate so a respawn or cooldown is never printed twice.
public struct PilotReadout: Equatable, Sendable {
    public var weapon = "STANDARD"
    public var buffs = ""
    public var readiness = "READY"
    public var fireLabel = "FIRE"
    public var fireHint = "HOLD TO FIRE"
    public var progress = 1.0
    public var capacity = 5
    public var available = 5
    public var firingSeconds: Double?
    public var locked = false
    public var unlimited = false

    public init(tank: ArenaTank, snapshot: ArenaSnapshot, infinity: Bool, paused: Bool = false,
                online: Bool = true) {
        let alive = tank.hp > 0
        unlimited = alive && tank.starmanTime > 0
        capacity = tank.power == "rapid" ? 115 : tank.power == "scatter" ? 12 : ["homing", "grenade", "laser", "cannon"].contains(tank.power) ? 3 : 5
        let boosted = Set(snapshot.boostedBulletIds)
        let allOwned = snapshot.bullets.filter { $0.owner == tank.id }
        let ordinary = allOwned.filter { !boosted.contains($0.id) }
        // Normalized fixed packets retain the authoritative count even while
        // rendering its projectiles on the delayed remote-entity timeline.
        let used = tank.power == "laser" ? max(0, 3 - tank.charges) : infinity ? tank.ammoUsed : max(tank.ammoUsed, ordinary.count)
        available = alive ? max(0, capacity - used) : 0
        // Boosted grenades still detonate; only ammunition-slot accounting
        // excludes Starman shots.
        let ownedGrenades = allOwned.filter { $0.kind == "grenade" }
        let grenadeLife = infinity ? tank.grenadeLife : max(tank.grenadeLife, ownedGrenades.map(\.life).max() ?? 0)
        let grenades = infinity ? (grenadeLife > 0 ? tank.grenades : 0) : max(tank.grenades, ownedGrenades.count)
        let projectileLocked = tank.locked || snapshot.bullets.contains { bullet in
            guard (bullet.kind == "homing" || bullet.kind == "grenade"), bullet.target == tank.id, bullet.owner != tank.id else { return false }
            let owner = snapshot.tanks.first { $0.id == bullet.owner }
            return snapshot.rules?.friendlyFire == true || owner == nil || owner?.team == 0 || owner?.team != tank.team
        }
        let names = ["rapid": "MACHINE GUN", "scatter": "SHOTGUN", "homing": "HOMING", "grenade": "GRENADE", "laser": "LASER", "cannon": "CANNON"]
        let base = names[tank.power] ?? "STANDARD"
        if alive {
            if grenades > 0 { weapon = "GRENADE, \(String(format: "%.1f", grenadeLife))s" }
            else if unlimited { weapon = base + ", ∞ AMMO" }
            else if tank.power.isEmpty { weapon = base }
            else { weapon = base + (["scatter", "homing", "grenade", "laser", "cannon"].contains(tank.power) ? " ×\(tank.charges)" : "") + ", \(tank.power == "rapid" ? "EXPIRES " : "")\(Int(ceil(tank.powerTime)))s" }
            if tank.power == "rapid" && !unlimited { firingSeconds = Double(max(0, min(180, tank.machineRounds))) / 60 }
            var lines: [String] = []
            if tank.shield > 0 { lines.append("SHD×\(min(5, max(1, tank.shieldCharges))) \(Int(ceil(tank.shield)))s") }
            if tank.speedTime > 0 { lines.append("SPD×\(min(5, max(1, tank.speedStacks))) \(Int(ceil(tank.speedTime)))s") }
            if tank.starmanTime > 0 { lines.append("STAR \(Int(ceil(tank.starmanTime)))s") }
            else if tank.ghostTime > 0 { lines.append("GHO \(Int(ceil(tank.ghostTime)))s") }
            buffs = lines.count > 2 ? lines.map {
                $0.hasPrefix("SHD") ? String($0.split(separator: " ")[0]) : $0.replacingOccurrences(of: " ([0-9]+)s$", with: "$1", options: .regularExpression)
            }.joined(separator: " ") : lines.joined(separator: ", ")
        } else { weapon = "" }
        var unavailable: (text: String, label: String, progress: Double, hint: String?)?
        if snapshot.result != nil || snapshot.phase == "matchOver" { unavailable = ("MATCH COMPLETE", "DONE", 1, nil) }
        else if infinity {
            if !alive { unavailable = (paused && online ? "RESPAWN HELD" : "RESPAWN \(String(format: "%.1f", tank.respawnTime))s", "OUT", 0, nil) }
            else if paused { unavailable = ("PAUSED", "PAUSED", 1, nil) }
        } else if snapshot.phase == "roundOver" { unavailable = ("ROUND COMPLETE", "DONE", 1, nil) }
        else if paused || snapshot.phase == "paused" { unavailable = ("PAUSED", "PAUSED", 1, nil) }
        else if snapshot.phase == "countdown" { unavailable = ("GET READY", "FIRE", 0, nil) }
        else if snapshot.phase != "playing" { unavailable = ("READY", "FIRE", 1, nil) }
        else if let survival = snapshot.objectives?.survival, survival.status == "break" {
            unavailable = ("NEXT WAVE \(Int(ceil(survival.breakTime)))s", "WAIT", 0, "NEXT WAVE")
        } else if !alive {
            let mode = snapshot.objectives?.mode ?? snapshot.rules?.mode ?? "elimination"
            let text = mode == "survival" ? "BACK NEXT WAVE" : ["ctf", "koth"].contains(mode) && snapshot.objectives?.suddenDeath != true
                ? "RESPAWN \(String(format: "%.1f", tank.respawnTime))s" : "OUT"
            unavailable = (text, "OUT", 0, nil)
        }
        if unavailable == nil && tank.spawnProtected && tank.invulnerable > 0 { unavailable = ("SPAWN PROTECTION", "WAIT", 0, "WAIT TO FIRE") }
        locked = unavailable == nil && projectileLocked
        fireHint = tank.power == "grenade" ? "TAP TO THROW" : "HOLD TO FIRE"
        if let unavailable {
            readiness = unavailable.text; fireLabel = unavailable.label; progress = unavailable.progress
            fireHint = unavailable.hint ?? fireHint
        } else if grenades > 0 { readiness = "DETONATE READY"; fireLabel = "BOOM"; fireHint = "TAP TO DETONATE" }
        else {
            let cooldown = unlimited ? 0 : tank.cooldown
            let free = unlimited ? Int.max : tank.power == "laser" ? tank.charges : available
            let need = tank.power == "scatter" ? 3 : 1
            let cooldowns: [String: Double] = ["cannon": 0.85 * 2 / 3, "laser": 0.85 * 2 / 3, "rapid": 0, "scatter": 0.54, "homing": 0.72, "grenade": 0.8]
            let fallback = cooldowns[tank.power] ?? 0.34
            let total = tank.cooldownTotal > 0 ? tank.cooldownTotal : fallback
            progress = cooldown > 0 ? max(0, min(1, 1 - cooldown / max(0.001, total))) : free < need ? 0 : 1
            if cooldown > 0 { let time = String(format: "%.1f", max(0.1, (cooldown * 10).rounded(.toNearestOrAwayFromZero) / 10)); readiness = "COOLDOWN \(time)s"; fireLabel = time + "s" }
            else if free < need { readiness = "WAITING FOR AMMO"; fireLabel = "WAIT" }
            if tank.power == "grenade" { fireHint = "TAP TO THROW" }
        }
    }
}
