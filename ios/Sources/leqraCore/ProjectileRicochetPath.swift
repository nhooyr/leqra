import Foundation

/// Read-only presentation of a proven authoritative ricochet. Guided/dragged
/// projectiles and mismatching endpoints retain the conservative held pose.
struct ProjectileRicochetPath {
    private struct Segment { var start: Double; var end: Double; var bullet: ArenaBullet }
    private var segments: [Segment] = []
    private let end: ArenaBullet
    private let span: Double

    init?(from first: ArenaBullet, to second: ArenaBullet, span: Double, maze: InfiniteMaze) {
        guard span > 0, span <= 0.1, first.id == second.id, first.owner == second.owner,
              first.kind == second.kind, ["", "rapid", "scatter", "cannon"].contains(first.kind),
              second.bounces > first.bounces, second.bounces - first.bounces <= 4,
              abs(first.life - second.life - span) <= 0.025 else { return nil }
        self.end = second; self.span = span
        let radius = first.kind == "rapid" ? 3.5 / 3 : first.kind == "cannon" ? 14 : 3.5
        let nudge = maze.world == nil ? 0.12 : 0.08
        var bullet = first, time = 0.0
        for _ in 0...4 {
            let remaining = span - time
            if remaining <= 1e-9 { break }
            let hit = maze.projectileHit(kind: first.kind, x: bullet.x, y: bullet.y,
                                          dx: bullet.vx * remaining, dy: bullet.vy * remaining, radius: radius)
            let duration = remaining * (hit?.fraction ?? 1)
            segments.append(Segment(start: time, end: time + duration, bullet: bullet))
            bullet.x += bullet.vx * duration; bullet.y += bullet.vy * duration; time += duration
            guard let hit else { break }
            bullet.x += hit.nx * nudge; bullet.y += hit.ny * nudge
            if hit.nx != 0 { bullet.vx = -bullet.vx }; if hit.ny != 0 { bullet.vy = -bullet.vy }
            bullet.bounces += 1
        }
        guard time >= span - 1e-8, bullet.bounces == second.bounces,
              hypot(bullet.x - second.x, bullet.y - second.y) <= 0.5,
              hypot(bullet.vx - second.vx, bullet.vy - second.vy) <= 0.5 else { return nil }
    }

    func sample(fraction: Double) -> ArenaBullet {
        let time = max(0, min(1, fraction)) * span
        guard time < span, let segment = segments.last(where: { $0.start <= time }) else { return end }
        var bullet = segment.bullet
        let elapsed = min(time, segment.end) - segment.start
        bullet.x += bullet.vx * elapsed; bullet.y += bullet.vy * elapsed
        bullet.life -= time
        return bullet
    }
}
