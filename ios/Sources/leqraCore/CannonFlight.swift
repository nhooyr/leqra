import Foundation

/// A terminal visual path produced by authority, including shots born and hit
/// between snapshots. These records never participate in combat or prediction.
public struct CannonFlightPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var tick: Double
    public init(x: Double, y: Double, tick: Double) { self.x = x; self.y = y; self.tick = tick }
}

public struct CannonFlight: Codable, Equatable, Sendable {
    public var id: Int
    public var owner: Int
    public var colorIndex: Int
    public var startTick: Double
    public var endTick: Double
    public var points: [CannonFlightPoint]
    public var kind: String?
    public var radius: Double?
    public init(id: Int, owner: Int, colorIndex: Int, startTick: Double, endTick: Double, points: [CannonFlightPoint], kind: String? = nil, radius: Double? = nil) {
        self.id = id; self.owner = owner; self.colorIndex = colorIndex
        self.startTick = startTick; self.endTick = endTick; self.points = points
        self.kind = kind; self.radius = radius
    }

    var valid: Bool {
        guard id > 0, owner >= 0, (0..<8).contains(colorIndex), (2...32).contains(points.count),
              startTick.isFinite, endTick.isFinite, endTick >= startTick, endTick - startTick <= 1_200,
              points.first?.tick == startTick, points.last?.tick == endTick,
              ["cannon", "regular", "rapid", "scatter", "homing", "grenade"].contains(kind ?? "cannon"),
              radius == nil || radius!.isFinite && radius! >= 0 && radius! <= 32 else { return false }
        var previous = startTick
        for point in points {
            guard point.x.isFinite, point.y.isFinite, point.tick.isFinite,
                  abs(point.x) <= 1e12, abs(point.y) <= 1e12,
                  point.tick >= previous, point.tick <= endTick else { return false }
            previous = point.tick
        }
        return true
    }

    func sample(tick: Double) -> ArenaBullet {
        let time = min(endTick, max(startTick, tick))
        var first = points[0], second = points[1]
        for next in points.dropFirst() {
            second = next
            if next.tick >= time { break }
            first = next
        }
        let span = second.tick - first.tick
        let fraction = span > 0 ? min(1, max(0, (time - first.tick) / span)) : 1
        return ArenaBullet(id: id, x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction,
            vx: span > 0 ? (second.x - first.x) * 60 / span : 0,
            vy: span > 0 ? (second.y - first.y) * 60 / span : 0,
            owner: owner, kind: kind == "regular" ? "" : kind ?? "cannon", colorIndex: colorIndex, life: max(0, (endTick - time) / 60))
    }
}

/// Bounded presentation only. A short/past flight gets a 50ms traversal of the
/// exact server path, so even a point-blank kill has a visible cannon glyph.
final class CannonFlightPresenter {
    private struct Active { var flight: CannonFlight; var effect: ArenaEffect; var displayed = false; var replayBegan: Double? }
    private var active: [Int: Active] = [:]
    private var seen = Set<Int>()
    private var order: [Int] = []
    private var readyEffects: [ArenaEffect] = []
    var hasPending: Bool { !active.isEmpty }

    func reset() { active.removeAll(keepingCapacity: true); seen.removeAll(keepingCapacity: true); order.removeAll(keepingCapacity: true); readyEffects.removeAll(keepingCapacity: true) }

    func accept(_ effects: [ArenaEffect], baseline: Bool = false, throughTick: Double? = nil) {
        for effect in effects {
            guard let flight = effect.flight, flight.valid,
                  throughTick == nil || flight.endTick <= throughTick! + 1e-7,
                  seen.insert(flight.id).inserted else { continue }
            order.append(flight.id)
            if order.count > 512 { seen.remove(order.removeFirst()) }
            guard !baseline else { continue }
            if active.count >= 256, let oldest = active.min(by: { $0.value.flight.endTick < $1.value.flight.endTick })?.key { active.removeValue(forKey: oldest) }
            active[flight.id] = Active(flight: flight, effect: effect)
        }
    }

    func append(to bullets: inout [ArenaBullet], tick: Double, now: Double) {
        guard !active.isEmpty else { return }
        var replacements: [Int: ArenaBullet] = [:]
        for (id, var value) in active {
            let flight = value.flight
            guard tick >= flight.startTick else { continue }
            let short = flight.endTick - flight.startTick < 3
            if value.replayBegan == nil, short || tick > flight.endTick && !value.displayed { value.replayBegan = now }
            if let began = value.replayBegan {
                let age = max(0, now - began)
                guard age <= 0.05 else { finish(id, effect: value.effect); continue }
                replacements[id] = flight.sample(tick: flight.startTick + (flight.endTick - flight.startTick) * min(1, age / 0.05))
            } else {
                guard tick <= flight.endTick else { finish(id, effect: value.effect); continue }
                replacements[id] = flight.sample(tick: tick)
            }
            value.displayed = true
            active[id] = value
        }
        guard !replacements.isEmpty else { return }
        bullets.removeAll { replacements[$0.id] != nil }
        for id in replacements.keys.sorted() { bullets.append(replacements[id]!) }
    }

    private func finish(_ id: Int, effect: ArenaEffect) {
        active.removeValue(forKey: id)
        readyEffects.append(effect)
    }

    func effects(_ source: [ArenaEffect]) -> [ArenaEffect] {
        var result = source.filter { effect in effect.flight.map { active[$0.id] == nil } ?? true }
        let ids = Set(result.map(\.id))
        result.append(contentsOf: readyEffects.filter { !ids.contains($0.id) })
        readyEffects.removeAll(keepingCapacity: true)
        return result
    }
}
