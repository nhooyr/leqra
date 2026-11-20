import Foundation

/// State for the opt-in renderer diagnostic, never gameplay or prediction.
/// Source events can expire while their accepted presentation is still pending.
public struct ContactProbeCase {
    public enum Result: String { case passed, damageBeforeEndpoint }
    public private(set) var result: Result?
    public private(set) var frames = 0
    public private(set) var creditedSeconds = 0.0
    private var contactEffect: ArenaEffect?
    private var flight: CannonFlight?
    private var endpointFrame: Int?
    public init() {}

    public var canAdvance: Bool { creditedSeconds >= 0.3 && result != nil || creditedSeconds >= 1 }

    public mutating func observe(authoritative: ArenaSnapshot, visible: ArenaSnapshot, dt: Double) {
        frames += 1
        creditedSeconds += dt.isFinite ? min(0.1, max(0, dt)) : 0
        guard result == nil else { return }
        if contactEffect == nil { contactEffect = authoritative.effects.first { $0.contact != nil } }
        guard let effect = contactEffect, let contact = effect.contact,
            let body = visible.tanks.first(where: {
                $0.id == contact.target && $0.spawnSerial == contact.spawnSerial
            })
        else { return }
        if flight == nil, contact.projectileId > 0 {
            flight = authoritative.effects.first { $0.flight?.id == contact.projectileId }?.flight
        }
        if let flight, let end = flight.points.last,
            let bullet = visible.bullets.first(where: { $0.id == flight.id }),
            hypot(bullet.x - end.x, bullet.y - end.y) < 1e-7, body.hp > 0,
            hypot(bullet.x - body.x, bullet.y - body.y) <= 17 + (flight.radius ?? 0) + 1e-7
        {
            endpointFrame = endpointFrame ?? frames
        }
        if contact.projectileId == 0, body.hp > 0 {
            let beam = visible.effects.contains { $0.kind == "laser" }
            let touching =
                contact.kind == "starman"
                && visible.tanks.contains {
                    $0.id == effect.owner && hypot($0.x - body.x, $0.y - body.y) <= 34.0000001
                }
            let cannon =
                contact.kind == "cannon"
                && (visible.bullets.contains {
                    $0.kind == "cannon" && $0.owner == effect.owner
                        && hypot($0.x - body.x, $0.y - body.y) <= 31.0000001
                }
                    || visible.effects.contains {
                        $0.kind == "impact" && $0.owner == effect.owner
                            && hypot($0.x - body.x, $0.y - body.y) <= 31.0000001
                    })
            if beam || touching || cannon { endpointFrame = endpointFrame ?? frames }
        }
        if visible.effects.contains(where: { $0.id == effect.id }) || body.hp <= 0 {
            result = endpointFrame.map { $0 < frames } == true ? .passed : .damageBeforeEndpoint
        }
    }

    /// Each isolated simulation restarts its IDs. Keep the real renderer/audio
    /// deduplicators active while giving every diagnostic case fresh events.
    public static func renderSnapshot(_ snapshot: ArenaSnapshot, episode: Int) -> ArenaSnapshot {
        var snapshot = snapshot
        let offset = (episode + 1) * 1_000_000
        for index in snapshot.bullets.indices { snapshot.bullets[index].id += offset }
        snapshot.boostedBulletIds = snapshot.boostedBulletIds.map { $0 + offset }
        for index in snapshot.effects.indices {
            snapshot.effects[index].id += offset
            if snapshot.effects[index].flight != nil { snapshot.effects[index].flight!.id += offset }
            if let id = snapshot.effects[index].contact?.projectileId, id > 0 {
                snapshot.effects[index].contact!.projectileId += offset
            }
        }
        return snapshot
    }
}
