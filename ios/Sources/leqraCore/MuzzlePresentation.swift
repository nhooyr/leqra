import Foundation

/// Keep the drawn barrel on the incoming side of cover. This changes no hitboxes.
public enum MuzzlePresentation {
    public static func retraction(tank: ArenaTank, maze: InfiniteMaze?, recoil: Double? = nil) -> Double {
        let radius: Double
        switch tank.power {
        case "rapid": radius = 3.5 / 3
        case "homing": radius = 5
        case "grenade": radius = 6
        case "laser": radius = 3
        default: radius = 3.5
        }
        var hit = maze?.projectileHit(
            kind: "", x: tank.x, y: tank.y,
            dx: cos(tank.angle) * 30, dy: sin(tank.angle) * 30, radius: radius)
        var clearance = radius
        if hit == nil && tank.ghostTime > 0 {
            hit = maze?.projectileHit(
                kind: "", x: tank.x, y: tank.y,
                dx: cos(tank.angle) * 30, dy: sin(tank.angle) * 30, radius: 0)
            clearance = 0.5
        }
        let fraction = hit?.fraction ?? 1
        let obstruction = 30 * (1 - max(0, min(1, fraction))) - min(2, max(0, clearance - 0.5))
        return max(max(0, min(1, recoil ?? tank.recoil)) * 4, obstruction)
    }
}
