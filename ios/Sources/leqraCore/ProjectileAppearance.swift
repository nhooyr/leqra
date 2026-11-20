import Foundation

public enum ProjectileAppearance {
    /// Rapid has two authored velocities. Select its cached tracer from the
    /// projectile itself so a shot keeps its appearance after Starman expires.
    /// The head and authoritative collision radius are unchanged.
    public static func rapidTracerLength(_ bullet: ArenaBullet) -> Int {
        guard bullet.kind == "rapid" else { return 0 }
        let speed = hypot(bullet.vx, bullet.vy)
        return speed.isFinite && speed > 846 * 1.5 ? 16 : 8
    }

    /// Fast tracers can point back into the wall immediately after a bounce.
    /// The renderer caches this point at birth/direction changes and briefly
    /// draws only the unchanged head until it has moved clear of the wall.
    public static func rapidTailWallPoint(_ bullet: ArenaBullet, maze: InfiniteMaze) -> (
        x: Double, y: Double
    )? {
        guard rapidTracerLength(bullet) == 16 else { return nil }
        let speed = hypot(bullet.vx, bullet.vy)
        let dx = -bullet.vx / speed * 16
        let dy = -bullet.vy / speed * 16
        guard
            let hit = maze.projectileHit(
                kind: "rapid", x: bullet.x, y: bullet.y, dx: dx, dy: dy, radius: 3.5 / 3)
        else { return nil }
        return (bullet.x + dx * hit.fraction, bullet.y + dy * hit.fraction)
    }
}
