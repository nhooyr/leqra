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

    func sample(tick: Double, instantaneousFraction: Double? = nil) -> ArenaBullet {
        let time = min(endTick, max(startTick, tick))
        var first = points[0], second = points[1]
        for next in points.dropFirst() {
            second = next
            if next.tick >= time { break }
            first = next
        }
        var span = second.tick - first.tick
        var fraction = span > 0 ? min(1, max(0, (time - first.tick) / span)) : 1
        if time >= endTick, instantaneousFraction == nil {
            first = points[points.count - 2]; second = points[points.count - 1]
            span = second.tick - first.tick; fraction = 1
        }
        if endTick == startTick, let progress = instantaneousFraction {
            let cursor = min(1, max(0, progress)) * Double(points.count - 1)
            let index = min(points.count - 2, Int(cursor))
            first = points[index]; second = points[index + 1]
            fraction = cursor - Double(index); span = 3 / Double(points.count - 1)
        }
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
    private struct Active {
        var flight: CannonFlight; var effect: ArenaEffect
        var displayed = false; var replayBegan: Double?; var replayStart: Double?
        var endpointShown = false
    }
    private struct PendingContact { var effect: ArenaEffect; var contact: ImpactContact; var endpointFrame: UInt64? }
    private struct Release { var spawn: Int; var x: Double; var y: Double; var angle: Double; var began: Double }
    private var active: [Int: Active] = [:]
    private var seen = Set<Int>()
    private var order: [Int] = []
    private var completed = Set<Int>()
    private var completedOrder: [Int] = []
    private var observed = Set<Int>()
    private var observedOrder: [Int] = []
    private var contacts: [Int: PendingContact] = [:]
    private var seenContacts = Set<Int>()
    private var contactOrder: [Int] = []
    private var readyEffects: [ArenaEffect] = []
    private var roundEndEffects: [Int: ArenaEffect] = [:]
    private var baselineEffectID = 0
    private var effectHighWater = 0
    private var presentationLimit = 1_024
    private var presentedEffects = Set<Int>()
    private var presentedOrder: [Int] = []
    private var frame: UInt64 = 0
    private var playbackTick = 0.0
    private var authorityTick = 0.0
    private var localID = -1
    private var renderTime = 0.0
    private var lives: [Int: Int] = [:]
    private var knownBodies: [Int: ArenaTank] = [:]
    private var bodyOrder: [Int] = []
    private var heldBodies: [Int: ArenaTank] = [:]
    private var releases: [Int: Release] = [:]
    var hasPending: Bool { !active.isEmpty || !contacts.isEmpty }

    func reset() {
        active.removeAll(keepingCapacity: true); seen.removeAll(keepingCapacity: true); order.removeAll(keepingCapacity: true)
        completed.removeAll(keepingCapacity: true); completedOrder.removeAll(keepingCapacity: true)
        observed.removeAll(keepingCapacity: true); observedOrder.removeAll(keepingCapacity: true)
        contacts.removeAll(keepingCapacity: true); seenContacts.removeAll(keepingCapacity: true); contactOrder.removeAll(keepingCapacity: true)
        readyEffects.removeAll(keepingCapacity: true); baselineEffectID = 0; frame = 0; playbackTick = 0; authorityTick = 0; localID = -1
        effectHighWater = 0; presentationLimit = 1_024
        presentedEffects.removeAll(keepingCapacity: true); presentedOrder.removeAll(keepingCapacity: true)
        roundEndEffects.removeAll(keepingCapacity: true)
        lives.removeAll(keepingCapacity: true); heldBodies.removeAll(keepingCapacity: true); releases.removeAll(keepingCapacity: true)
        knownBodies.removeAll(keepingCapacity: true); bodyOrder.removeAll(keepingCapacity: true)
    }

    func accept(_ effects: [ArenaEffect], baseline: Bool = false, throughTick: Double? = nil, tanks: [ArenaTank]? = nil) {
        if let tanks {
            presentationLimit = min(32_768, max(1_024, tanks.count * 128))
            for tank in tanks {
                if knownBodies[tank.id] == nil { bodyOrder.append(tank.id) }
                knownBodies[tank.id] = tank; lives[tank.id] = tank.spawnSerial
            }
            while bodyOrder.count > 4_096 { let id = bodyOrder.removeFirst(); knownBodies.removeValue(forKey: id); lives.removeValue(forKey: id) }
            contacts = contacts.filter { entry in
                lives[entry.value.contact.target].map { $0 == entry.value.contact.spawnSerial } != false
            }
        }
        let priorHighWater = effectHighWater
        effectHighWater = max(effectHighWater, effects.map(\.id).max() ?? 0)
        if baseline { baselineEffectID = max(baselineEffectID, effects.map(\.id).max() ?? 0) }
        for effect in effects {
            guard effect.id > priorHighWater, let flight = effect.flight, flight.valid,
                  throughTick == nil || flight.endTick <= throughTick! + 1e-7,
                  seen.insert(flight.id).inserted else { continue }
            order.append(flight.id)
            if order.count > presentationLimit * 2 { seen.remove(order.removeFirst()) }
            guard !baseline else { continue }
            if active.count >= presentationLimit, let oldest = active.min(by: { $0.value.flight.endTick < $1.value.flight.endTick })?.key { finish(oldest, effect: active[oldest]!.effect) }
            active[flight.id] = Active(flight: flight, effect: effect, displayed: observed.contains(flight.id))
        }
        for effect in effects {
            guard effect.id > priorHighWater, let contact = effect.contact, contact.valid,
                  throughTick == nil || contact.tick <= throughTick! + 1e-7,
                  seenContacts.insert(effect.id).inserted else { continue }
            contactOrder.append(effect.id)
            if contactOrder.count > presentationLimit * 4 { seenContacts.remove(contactOrder.removeFirst()) }
            guard !baseline, effect.id > baselineEffectID else { continue }
            guard lives[contact.target].map({ $0 == contact.spawnSerial }) != false else { continue }
            if contacts.count >= presentationLimit * 2, let oldest = contacts.keys.min() { contacts.removeValue(forKey: oldest) }
            contacts[effect.id] = PendingContact(effect: effect, contact: contact)
        }
    }

    func append(to bullets: inout [ArenaBullet], tick: Double, now: Double, authorityTick: Double? = nil, localID: Int = -1) {
        frame &+= 1; playbackTick = tick; self.authorityTick = authorityTick ?? tick; self.localID = localID; renderTime = now
        for bullet in bullets where observed.insert(bullet.id).inserted {
            observedOrder.append(bullet.id)
            if observedOrder.count > presentationLimit * 2 { observed.remove(observedOrder.removeFirst()) }
        }
        bullets.removeAll { completed.contains($0.id) }
        var firstContact: [Int: Int] = [:]
        for (id, pending) in contacts { firstContact[pending.contact.target] = min(firstContact[pending.contact.target] ?? id, id) }
        let blockedFlights = Set(contacts.compactMap { entry in
            firstContact[entry.value.contact.target] != entry.key ? entry.value.contact.projectileId : nil
        })
        var replacements: [Int: ArenaBullet] = [:]
        for (id, var value) in active {
            let flight = value.flight
            if value.endpointShown {
                // A coalesced packet may contain shield contact followed by a
                // lethal contact at a different pose. Hold the later endpoint
                // until its own before-body has occupied a complete frame.
                if blockedFlights.contains(id) { replacements[id] = flight.sample(tick: flight.endTick) }
                else { finish(id, effect: value.effect) }
                continue
            }
            guard tick >= flight.startTick else { continue }
            let short = flight.endTick - flight.startTick < 3
            if value.replayBegan == nil, !value.displayed, short || tick > flight.endTick {
                value.replayBegan = now
                value.replayStart = short ? flight.startTick : max(flight.startTick, flight.endTick - 3)
            }
            if let began = value.replayBegan {
                let age = max(0, now - began)
                let fraction = min(1, age / 0.05), start = value.replayStart ?? flight.startTick
                replacements[id] = flight.sample(tick: start + (flight.endTick - start) * fraction, instantaneousFraction: fraction)
                if fraction == 1 { value.endpointShown = true }
            } else {
                replacements[id] = flight.sample(tick: tick)
                if tick >= flight.endTick { value.endpointShown = true }
            }
            value.displayed = true
            active[id] = value
        }
        bullets.removeAll { replacements[$0.id] != nil || completed.contains($0.id) }
        for id in replacements.keys.sorted() { bullets.append(replacements[id]!) }
        for (id, var pending) in contacts {
            let contact = pending.contact
            if contact.projectileId > 0, active[contact.projectileId] != nil { continue }
            guard firstContact[contact.target] == id else { continue }
            let clock = contact.projectileId == 0 && pending.effect.owner == localID ? self.authorityTick : tick
            guard completed.contains(contact.projectileId) || clock >= contact.tick else { continue }
            if contact.projectileId > 0, completed.contains(contact.projectileId) {
                contacts.removeValue(forKey: id); readyEffects.append(pending.effect)
            } else if let shown = pending.endpointFrame, shown < frame {
                contacts.removeValue(forKey: id); readyEffects.append(pending.effect)
            } else if pending.endpointFrame == nil {
                pending.endpointFrame = frame; contacts[id] = pending
            }
        }
    }

    private func finish(_ id: Int, effect: ArenaEffect) {
        active.removeValue(forKey: id)
        if completed.insert(id).inserted { completedOrder.append(id) }
        if completedOrder.count > presentationLimit * 2 { completed.remove(completedOrder.removeFirst()) }
        readyEffects.append(effect)
    }

    /// Restore only the visible body/defenses. Scores and all authoritative
    /// state remain newest; a newer spawn can never be revived by an old hit.
    func applyContacts(to tanks: inout [ArenaTank], from previous: [Int: ArenaTank] = [:], previousTick: Double? = nil,
                       pathClear: ((ArenaTank, ArenaTank) -> Bool)? = nil) {
        var firstByTarget: [Int: PendingContact] = [:]
        for pending in contacts.values {
            if firstByTarget[pending.contact.target].map({ $0.effect.id < pending.effect.id }) != true { firstByTarget[pending.contact.target] = pending }
        }
        let presentIDs = Set(tanks.map(\.id))
        for (id, pending) in firstByTarget where !presentIDs.contains(id) {
            // A view boundary or roaming-budget trim can remove a known corpse
            // before its terminal event expires. Retain that body's known art
            // only through contact; never invent an unseen pilot's appearance.
            if let known = knownBodies[id], known.spawnSerial == pending.contact.spawnSerial {
                tanks.append(pending.contact.before.applying(to: known))
            }
        }
        for index in tanks.indices {
            let current = tanks[index]
            guard let pending = firstByTarget[current.id], current.spawnSerial == pending.contact.spawnSerial else {
                if let held = heldBodies.removeValue(forKey: current.id), held.spawnSerial == current.spawnSerial,
                   current.hp > 0, hypot(held.x - current.x, held.y - current.y) <= 64 {
                    releases[current.id] = Release(spawn: current.spawnSerial, x: held.x - current.x, y: held.y - current.y,
                        angle: atan2(sin(held.angle - current.angle), cos(held.angle - current.angle)), began: renderTime)
                }
                if let release = releases[current.id] {
                    let fraction = min(1, max(0, (renderTime - release.began) / 0.04))
                    if release.spawn != current.spawnSerial || current.hp <= 0 || fraction >= 1 { releases.removeValue(forKey: current.id); continue }
                    let remaining = 1 - fraction * fraction * (3 - 2 * fraction)
                    var visual = current
                    visual.x += release.x * remaining; visual.y += release.y * remaining; visual.angle += release.angle * remaining
                    if pathClear?(current, visual) != false { tanks[index] = visual }
                    else { releases.removeValue(forKey: current.id) }
                }
                continue
            }
            let contact = pending.contact
            var visual = contact.before.applying(to: tanks[index])
            if tanks[index].id != localID, let old = previous[visual.id], old.hp > 0,
               old.spawnSerial == visual.spawnSerial, let previousTick, contact.tick > previousTick,
               playbackTick < contact.tick, pathClear?(old, visual) != false {
                let fraction = min(1, max(0, (playbackTick - previousTick) / (contact.tick - previousTick)))
                visual.x = old.x + (visual.x - old.x) * fraction; visual.y = old.y + (visual.y - old.y) * fraction
                visual.angle = old.angle + atan2(sin(visual.angle - old.angle), cos(visual.angle - old.angle)) * fraction
            }
            tanks[index] = visual
            heldBodies[visual.id] = visual; releases.removeValue(forKey: visual.id)
        }
        let liveIDs = Set(tanks.map(\.id))
        heldBodies = heldBodies.filter { liveIDs.contains($0.key) }; releases = releases.filter { liveIDs.contains($0.key) }
    }

    func effects(_ source: [ArenaEffect]) -> [ArenaEffect] {
        if hasPending {
            for effect in source where effect.kind == "roundEnd" && effect.id > baselineEffectID {
                if roundEndEffects.count < 8 { roundEndEffects[effect.id] = effect }
            }
        } else {
            readyEffects.append(contentsOf: roundEndEffects.values); roundEndEffects.removeAll(keepingCapacity: true)
        }
        var result = source.filter { effect in
            guard effect.id > baselineEffectID, contacts[effect.id] == nil,
                  effect.flight.map({ active[$0.id] == nil }) ?? true else { return false }
            if effect.kind == "roundEnd", hasPending { return false }
            if let contact = effect.contact, lives[contact.target].map({ $0 == contact.spawnSerial }) == false { return false }
            let ownInstant = effect.owner == localID && (effect.kind == "laser" || effect.kind == "shot:laser" || effect.contact?.projectileId == 0)
            return effect.tick.map { Double($0) <= (ownInstant ? authorityTick : playbackTick) + 1e-7 } ?? true
        }
        let ids = Set(result.map(\.id))
        result.append(contentsOf: readyEffects.filter { effect in
            !ids.contains(effect.id) && effect.contact.map { contact in lives[contact.target].map { $0 == contact.spawnSerial } != false } != false
        })
        readyEffects.removeAll(keepingCapacity: true)
        return result.filter { effect in
            guard presentedEffects.insert(effect.id).inserted else { return false }
            presentedOrder.append(effect.id)
            if presentedOrder.count > presentationLimit * 4 { presentedEffects.remove(presentedOrder.removeFirst()) }
            return true
        }
    }
}
