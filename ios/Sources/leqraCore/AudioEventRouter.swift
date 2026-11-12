import Foundation

public struct AudioCueRequest: Equatable, Sendable {
    public let cue: AudioCue
    public let local: Bool

    public init(cue: AudioCue, local: Bool = true) {
        self.cue = cue
        self.local = local
    }
}

/// Chooses browser-equivalent cues from presentation snapshots. Each consumer
/// owns one router; skipped, muted, or paused history can be baselined with reset.
public struct AudioEventRouter: Sendable {
    private var generation: Int?
    private var highestEffectID = 0
    private var bounceCounts: [Int: Int] = [:]
    private var previousPhase: String?
    private var countdownNumber: Int?
    private var lastExplosion = -Double.infinity
    private var lastGrenade = -Double.infinity
    private var lastRicochet = -Double.infinity
    private var lastMachineShot = -Double.infinity
    private var homingLocked = false
    private var lastHomingWarning = -Double.infinity

    public init() {}

    public mutating func reset() { self = AudioEventRouter() }

    public mutating func consume(snapshot: ArenaSnapshot, localID: Int,
                                 infinity: Bool, online: Bool, now: Double) -> [AudioCueRequest] {
        guard now.isFinite else { return [] }
        var requests: [AudioCueRequest] = []
        let localTank = snapshot.tanks.first { $0.id == localID }
        if generation != snapshot.generation {
            reset()
            generation = snapshot.generation
            highestEffectID = snapshot.effects.map(\.id).max() ?? 0
            for bullet in snapshot.bullets { bounceCounts[bullet.id] = bullet.bounces }
            // Countdown is current presentation, rather than retained combat
            // history. Joining a live round must not replay its effects or GO.
            appendPhaseCues(snapshot, infinity: infinity, online: online, into: &requests)
            appendHomingWarning(snapshot, localTank: localTank, now: now, into: &requests)
            return requests
        }

        appendPhaseCues(snapshot, infinity: infinity, online: online, into: &requests)
        appendHomingWarning(snapshot, localTank: localTank, now: now, into: &requests)
        var bounced = false
        var liveBounces: [Int: Int] = [:]
        for bullet in snapshot.bullets {
            let previous = bounceCounts[bullet.id]
            liveBounces[bullet.id] = max(previous ?? bullet.bounces, bullet.bounces)
            if let previous, bullet.bounces > previous,
               !infinity || near(bullet.x, bullet.y, localTank: localTank, radius: 588) {
                bounced = true
            }
        }
        bounceCounts = liveBounces
        if bounced, now - lastRicochet >= AudioSynthesis.ricochetInterval {
            lastRicochet = now
            requests.append(AudioCueRequest(cue: .ricochet))
        }

        for effect in snapshot.effects.sorted(by: { $0.id < $1.id }) {
            guard effect.id > 0, effect.id > highestEffectID else { continue }
            highestEffectID = effect.id
            let own = (effect.player ?? effect.owner) == localID
            guard !infinity || effect.owner == localID || near(effect.x, effect.y, localTank: localTank, radius: 504) else { continue }
            let shot: AudioCue?
            switch effect.kind {
            case "shot", "shot:", "shot:regular": shot = .regular
            case "shot:rapid": shot = .rapid
            case "shot:scatter": shot = .scatter
            case "shot:laser": shot = .laser
            case "shot:homing": shot = .homing
            case "shot:grenade": shot = .grenade
            case "shot:cannon": shot = .cannon
            // Fixed network laser carries a visual beam and a separate shot
            // event. Infinity and native local simulation carry only the beam.
            case "laser": shot = online && !infinity ? nil : .laser
            default: shot = nil
            }
            if let shot {
                let shooter = snapshot.tanks.first { $0.id == (effect.player ?? effect.owner) }
                if shot == .rapid || (shooter?.starmanTime ?? 0) > 0 && shot != .grenade {
                    guard now - lastMachineShot >= AudioSynthesis.repeatedShotInterval else { continue }
                    lastMachineShot = now
                }
                requests.append(AudioCueRequest(cue: shot, local: own))
                continue
            }
            switch effect.kind {
            case "pickup":
                if infinity || !online || own { requests.append(AudioCueRequest(cue: .pickup, local: own)) }
            case "objective":
                if !infinity { requests.append(AudioCueRequest(cue: .pickup, local: own)) }
            case "shield": requests.append(AudioCueRequest(cue: .shield))
            case "impact": requests.append(AudioCueRequest(cue: .impact))
            case "blast":
                // A grenade has its own cooldown, so an unrelated recent tank
                // death cannot suppress it. Its victims share the death gate.
                if now - lastGrenade >= AudioSynthesis.explosionInterval {
                    lastGrenade = now; lastExplosion = now
                    requests.append(AudioCueRequest(cue: .grenadeExplosion))
                }
            case "hit":
                if now - lastExplosion >= AudioSynthesis.explosionInterval {
                    lastExplosion = now
                    requests.append(AudioCueRequest(cue: .explosion))
                }
            case "roundEnd":
                if online && !infinity {
                    requests.append(AudioCueRequest(cue: .onlineRoundEnd, local: effect.owner == localID))
                }
            default: break
            }
        }
        return requests
    }

    private mutating func appendHomingWarning(_ snapshot: ArenaSnapshot, localTank: ArenaTank?,
                                              now: Double, into requests: inout [AudioCueRequest]) {
        var locked = false
        if snapshot.phase == "playing", snapshot.result == nil, let tank = localTank, tank.hp > 0,
           snapshot.objectives?.survival?.status != "break" {
            locked = tank.locked || snapshot.bullets.contains { bullet in
                guard (bullet.kind == "homing" || bullet.kind == "grenade"),
                      bullet.target == tank.id, bullet.owner != tank.id else { return false }
                let owner = snapshot.tanks.first { $0.id == bullet.owner }
                return snapshot.rules?.friendlyFire == true || owner == nil || owner?.team == 0 || owner?.team != tank.team
            }
        }
        if locked && !homingLocked && now - lastHomingWarning > AudioSynthesis.homingWarningInterval {
            requests.append(AudioCueRequest(cue: .homingWarning))
            lastHomingWarning = now
        }
        homingLocked = locked
    }

    private mutating func appendPhaseCues(_ snapshot: ArenaSnapshot, infinity: Bool,
                                         online: Bool, into requests: inout [AudioCueRequest]) {
        defer { previousPhase = snapshot.phase }
        guard !infinity else { countdownNumber = nil; return }
        if snapshot.phase == "countdown", snapshot.phaseTime.isFinite,
           snapshot.phaseTime > 0, snapshot.phaseTime < Double(Int.max) {
            let number = Int(ceil(snapshot.phaseTime))
            if countdownNumber != number { requests.append(AudioCueRequest(cue: .countdown)) }
            countdownNumber = number
        } else {
            countdownNumber = nil
        }
        if !online, previousPhase == "countdown", snapshot.phase == "playing" {
            requests.append(AudioCueRequest(cue: .go))
        }
        if !online, previousPhase == "playing", snapshot.phase == "roundOver" {
            requests.append(AudioCueRequest(cue: snapshot.winner < 0 ? .roundDraw : .roundWin))
        }
    }

    private func near(_ x: Double, _ y: Double, localTank: ArenaTank?, radius: Double) -> Bool {
        guard let localTank else { return false }
        return hypot(x - localTank.x, y - localTank.y) <= radius
    }
}
