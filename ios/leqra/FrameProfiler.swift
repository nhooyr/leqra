import Foundation
import QuartzCore
import leqraCore

/// Opt-in, deterministic renderer workload. It never joins an online arena or
/// changes ordinary play. Measurements and device details stay outside Git.
@MainActor
final class FrameProfiler {
    let weapon: String
    private let projectileKind: String
    let count: Int
    let duration: Double
    let pans: Bool
    let buffs: Set<String>
    private let reflects: Bool
    private let motionMode: String?
    private let firstShotProbe: Bool
    private let badgeCountProbe: Bool
    private let hitMatrixProbe: Bool
    private let pickupMatrixProbe: Bool
    private let ammoRefillProbe: Bool
    private let emptyFireProbe: Bool
    private var ammoArena: PracticeArena?
    private var ammoEpisode = -1
    private var ammoAccumulator = 0.0
    private var ammoSteps = 0
    private var ammoChecks = 0
    private var ammoFailures: [String] = []
    let world: ArenaWorld?
    private var pickupEvents: [[String: Any]] = []
    private var pickupEvent: (episode: Int, stage: String, power: String)?
    private var previousPickupEvent = ""
    private var hitArena: PracticeArena?
    private var hitEpisode = -1
    private var hitAccumulator = 0.0
    private var hitFired = false
    private var hitFrame = 0
    private var endpointFrame: Int?
    private var hitResolved = false
    private var hitChecks = 0
    private var hitFailures: [String] = []
    private var hitLabel = ""
    private var previousBulletCount = 0
    private var firstShots: [[String: Any]] = []
    private var motionTank: ArenaTank?
    private let motionPresenter = TankMotionPresenter()
    private var motionTick: UInt64 = 0
    private var motionAccumulator = 0.0
    private var motionPose: ArenaTank?
    private var previousMotionPose: ArenaTank?
    private var previousVelocity: (x: Double, y: Double)?
    private var previousAcceleration: (x: Double, y: Double)?
    let maze: InfiniteMaze
    private var elapsed = 0.0
    private var reported = false
    private var samples: [[Double]] = []
    private var projectileCreations = 0
    private var effectCreations = 0
    private var mapRebuilds = 0

    init(arguments: [String]) {
        func argument(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        weapon = argument("--probe-weapon") ?? "regular"
        projectileKind = ["rapid", "scatter", "homing", "grenade", "cannon"].contains(weapon) ? weapon : ""
        count = min(2000, max(0, Int(argument("--probe-bullets") ?? "115") ?? 115))
        duration = min(60, max(5, Double(argument("--probe-seconds") ?? "12") ?? 12))
        pans = arguments.contains("--probe-pan")
        buffs = Set((argument("--probe-buffs") ?? "").split(separator: ",").map(String.init))
        reflects = arguments.contains("--probe-bounces")
        motionMode = argument("--probe-motion")
        firstShotProbe = arguments.contains("--probe-first-shot")
        badgeCountProbe = arguments.contains("--probe-badge-counts")
        hitMatrixProbe = arguments.contains("--probe-hit-matrix")
        pickupMatrixProbe = arguments.contains("--probe-pickup-matrix")
        ammoRefillProbe = arguments.contains("--probe-ammo-refill")
        emptyFireProbe = arguments.contains("--probe-empty-fire-feedback")
        if arguments.contains("--probe-fixed") {
            world = FixedArena(rules: RoomRules(), name: "PROBE", colorIndex: 0, botCount: 0, seed: 42).world
        } else { world = nil }
        maze = world.map { InfiniteMaze(world: $0) } ?? InfiniteMaze(seed: 42)
        if motionMode != nil {
            var tank = ArenaTank(id: 1, name: "PROBE PILOT", x: 420, y: 420)
            tank.speedTime = 120; tank.speedStacks = 5
            tank.ghostTime = 120; tank.starmanTime = 120
            motionTank = tank
        }
        samples.reserveCapacity(Int(duration * 150))
    }

    private func motionInput(at time: Double) -> GameInput {
        if motionMode == "touch" {
            return GameInput(stickX: cos(time * 6), stickY: sin(time * 6), touchAim: true)
        }
        return GameInput(forward: true, right: true, touchAim: false)
    }

    private func motionPresentation(_ tank: ArenaTank, input: GameInput, fraction: Double) -> ArenaTank {
        motionPresenter.present(tank: tank, input: input, tick: motionTick, fraction: fraction, move: {
            TankMovement.step(tank: &$0, input: $1, dt: $2, maze: self.maze)
        })
    }

    func snapshot(dt: Double) -> ArenaSnapshot {
        elapsed += dt
        if emptyFireProbe {
            return ArenaSnapshot(tick: UInt64(elapsed * 60), tanks: [ArenaTank(id: 1, name: "EMPTY", x: 420, y: 420, ammoUsed: 5)])
        }
        if hitMatrixProbe { return hitSnapshot(dt: dt) }
        if ammoRefillProbe { return ammoSnapshot(dt: dt) }
        if pickupMatrixProbe { return pickupSnapshot() }
        let time = elapsed, serial = Int(time * 60) + 200
        if var tank = motionTank {
            motionAccumulator += min(dt, 0.1)
            while motionAccumulator + 1e-9 >= 1 / 60 {
                TankMovement.step(tank: &tank, input: motionInput(at: time), dt: 1 / 60, maze: maze)
                motionTick += 1
                motionAccumulator = max(0, motionAccumulator - 1 / 60)
            }
            motionTank = tank
            motionPose = motionPresentation(tank, input: motionInput(at: time), fraction: motionAccumulator * 60)
        }
        let centerX = motionPose?.x ?? (420 + (pans ? time * 90 : 0)), centerY = motionPose?.y ?? 420.0
        var value = ArenaSnapshot()
        value.generation = 1; value.tick = UInt64(serial); value.phase = "playing"
        value.players = 1; value.tankCount = 8
        value.tanks = (0..<8).map { index in
            var tank = ArenaTank(id: index + 1, name: index == 0 ? "PROBE PILOT" : "ROVER \(index)",
                                 x: centerX + Double(index % 3) * 84, y: centerY + Double(index / 3) * 84,
                                 angle: time * 0.1, colorIndex: index, bot: index != 0)
            tank.power = weapon == "laser" ? "laser" : projectileKind
            tank.powerTime = 15
            tank.starmanTime = 8; tank.ghostTime = 8; tank.invulnerable = 8
            if buffs.contains("shield") || weapon == "shield" { tank.shield = 15; tank.shieldCharges = 5 }
            if buffs.contains("speed") || weapon == "speed" { tank.speedTime = 15; tank.speedStacks = 5 }
            tank.track = time * 30; tank.charges = 3; tank.machineRounds = 180
            if badgeCountProbe {
                let counts = [180, 179, 100, 99, 10, 9]
                tank.machineRounds = counts[Int(time * 2) % counts.count]
                tank.starmanTime = 0
                if index > 0 { tank.power = ["scatter", "homing", "grenade", "laser", "cannon", "speed", "shield"][index - 1] }
                tank.charges = 1 + Int(time * 2) % 3
            }
            if index == 0, let pose = motionPose {
                tank.x = pose.x; tank.y = pose.y; tank.angle = pose.angle; tank.track = pose.track
            }
            return tank
        }
        value.bullets.reserveCapacity(count)
        for index in 0..<count {
            let owner = index / 115, age = index % 115
            let angle = Double(owner) * 0.7 + Double(serial - age) * 0.018
            let distance = Double(age) * (weapon == "homing" ? 4 : 7) + (time * 60).truncatingRemainder(dividingBy: 1) * 7
            let speed = weapon == "homing" ? 240.0 : 420.0
            let rawX = cos(angle) * distance
            var x = centerX + rawX, velocity = cos(angle) * speed, bounces = 0
            if reflects && projectileKind != "cannon" {
                bounces = Int(floor((abs(rawX) + 210) / 420))
                let phase = (rawX + 210).truncatingRemainder(dividingBy: 840)
                let positive = phase < 0 ? phase + 840 : phase
                x = centerX - 210 + (positive <= 420 ? positive : 840 - positive)
                velocity *= bounces % 2 == 0 ? 1 : -1
            }
            var bullet = ArenaBullet(id: owner * 1_000_000 + serial - age,
                x: x, y: centerY + sin(angle) * distance,
                vx: velocity, vy: sin(angle) * speed,
                owner: owner + 1, kind: projectileKind,
                colorIndex: owner % 8, life: 5)
            bullet.bounces = bounces
            value.bullets.append(bullet)
        }
        value.boostedBulletIds = value.bullets.map(\.id)
        if weapon == "laser" {
            value.bullets = []
            value.effects = (max(1, serial - 31)...serial).map { id in
                let angle = Double(id) * 0.03
                return ArenaEffect(id: id, kind: "laser", x: centerX, y: centerY, owner: 1,
                    points: [BeamPoint(x: centerX, y: centerY),
                             BeamPoint(x: centerX + cos(angle) * 520, y: centerY + sin(angle) * 520)])
            }
        } else {
            value.effects = (max(1, serial - 31)...serial).map {
                ArenaEffect(id: $0, kind: "shot:" + projectileKind, x: centerX, y: centerY, owner: 1)
            }
        }
        value.leaderboard = value.tanks.map { LeaderboardEntry(id: $0.id, name: $0.name, colorIndex: $0.colorIndex) }
        if firstShotProbe {
            value.tanks = Array(value.tanks.prefix(1))
            value.tanks[0].starmanTime = 0; value.tanks[0].ghostTime = 0; value.tanks[0].invulnerable = 0
            let shot = Int(floor(max(0, time - 1) / 0.8)), age = time - 1 - Double(shot) * 0.8
            value.bullets = []; value.effects = []; value.boostedBulletIds = []
            if age >= 0 && age < 0.25 {
                value.bullets = [ArenaBullet(id: shot + 1, x: centerX + 32 + age * 420, y: centerY,
                    vx: 420, owner: 1, kind: projectileKind, life: 5)]
                value.effects = [ArenaEffect(id: shot + 1, kind: "shot:" + projectileKind, x: centerX, y: centerY, owner: 1)]
                if weapon == "laser" {
                    value.bullets = []
                    value.effects = [ArenaEffect(id: shot + 1, kind: "laser", owner: 1,
                        points: [BeamPoint(x: centerX + 28, y: centerY), BeamPoint(x: centerX + 400, y: centerY)])]
                }
            }
        }
        return value
    }

    private func pickupSnapshot() -> ArenaSnapshot {
        let powers = ["regular", "rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman"]
        let time = max(0, elapsed - 1), episode = Int(time / 0.55), age = time - Double(episode) * 0.55
        let power = powers[episode % powers.count]
        let stage = age < 0.1 || elapsed < 1 ? "plain" : age < 0.25 ? "pickup" : "fire"
        pickupEvent = (episode, stage, power)
        var tank = ArenaTank(id: 1, name: "PROBE PILOT", x: 420, y: 420, spawnSerial: 1)
        if stage != "plain" {
            switch power {
            case "shield": tank.shield = 15; tank.shieldCharges = 1
            case "speed": tank.speedTime = 15; tank.speedStacks = 1
            case "ghost": tank.ghostTime = 15
            case "starman": tank.starmanTime = 8
            case "regular": break
            default: tank.power = power; tank.powerTime = 15; tank.charges = 3; tank.machineRounds = 180
            }
        }
        var value = ArenaSnapshot(tick: UInt64(elapsed * 60), tanks: [tank])
        value.generation = 1; value.phase = "playing"; value.players = 1; value.tankCount = 1; value.world = world
        if stage == "pickup", power != "regular" {
            value.effects = [ArenaEffect(id: episode * 1000 + 1, kind: "pickup", x: 420, y: 420, owner: 1)]
        }
        if stage == "fire" {
            let kind = ["rapid", "scatter", "homing", "grenade", "cannon", "laser"].contains(power) ? power : ""
            let id = episode * 1000 + 2
            if kind == "laser" {
                value.effects = [ArenaEffect(id: id, kind: "laser", owner: 1, points: [BeamPoint(x: 448, y: 420), BeamPoint(x: 700, y: 420)])]
            } else {
                value.bullets = (0..<(kind == "scatter" ? 3 : 1)).map {
                    ArenaBullet(id: id + $0, x: 452 + (age - 0.25) * 420, y: 420 + Double($0) * 7, vx: 420, owner: 1, kind: kind, life: 5)
                }
                value.effects = [ArenaEffect(id: id, kind: "shot:" + kind, x: 420, y: 420, owner: 1)]
            }
        }
        value.leaderboard = [LeaderboardEntry(id: 1, name: tank.name)]
        return value
    }

    private func ammoSnapshot(dt: Double) -> ArenaSnapshot {
        let cases = ["rapid", "scatter", "homing", "grenade", "laser", "cannon", "shieldExpiry", "speedExpiry", "ghostExpiry", "starmanExpiry", "weaponExpiry"]
        let episode = Int(elapsed / 0.65), scenario = cases[episode % cases.count]
        let expiry = scenario.hasSuffix("Expiry")
        if episode != ammoEpisode {
            ammoEpisode = episode; ammoAccumulator = 0; ammoSteps = 0
            var tank = ArenaTank(id: 1, name: "AMMO CHECK", x: 42, y: 42, spawnSerial: 1,
                cooldown: expiry ? 0.5 : 0, powerTime: scenario == "weaponExpiry" ? 0.001 : 15,
                power: expiry ? "cannon" : scenario, charges: scenario == "rapid" ? 0 : 1,
                machineRounds: scenario == "rapid" ? 1 : 0, ammoEpoch: 41)
            if scenario == "shieldExpiry" { tank.shield = 0.001; tank.shieldCharges = 1 }
            if scenario == "speedExpiry" { tank.speedTime = 0.001; tank.speedStacks = 5 }
            if scenario == "ghostExpiry" { tank.ghostTime = 0.001 }
            if scenario == "starmanExpiry" { tank.starmanTime = 0.001 }
            ammoArena = PracticeArena(seed: 42, name: tank.name, colorIndex: 0, botCount: 0, world: world, initialTanks: [tank])
        }
        let arena = ammoArena!
        ammoAccumulator += min(dt, 0.1)
        while ammoAccumulator + 1e-9 >= 1 / 60 {
            arena.step(input: GameInput(fire: !expiry || ammoSteps > 0), dt: 1 / 60)
            ammoSteps += 1; ammoAccumulator = max(0, ammoAccumulator - 1 / 60)
            let tank = arena.snapshot.tanks[0]
            if ammoSteps == 1 {
                ammoChecks += 1
                let standard = !expiry || scenario == "weaponExpiry"
                if tank.ammoEpoch != 42 || tank.cooldown != 0 || tank.ammoUsed != 0
                    || tank.power != (standard ? "" : "cannon") || tank.charges != (standard ? 0 : 3) {
                    ammoFailures.append(scenario + ": magazine did not refill before firing")
                }
            } else if ammoSteps == 2 {
                ammoChecks += 1
                if !arena.snapshot.bullets.contains(where: { $0.ammoEpoch == 42 }) {
                    ammoFailures.append(scenario + ": held fire did not use the new magazine")
                }
            }
        }
        var visible = arena.presentationSnapshot(fraction: ammoAccumulator * 60, now: elapsed)
        visible.generation = episode + 1
        return visible
    }

    /// The real offline simulation and presenter drive this opt-in device
    /// matrix. The report checks contact geometry on the exact snapshot passed
    /// to SpriteKit, including shields and every stacked movement/fire buff.
    private func hitSnapshot(dt: Double) -> ArenaSnapshot {
        let weapons = ["regular", "rapid", "scatter", "homing", "grenade", "cannon", "laser", "starman"]
        let profiles = ["plain", "starman", "speed", "ghost", "shield"]
        let episode = Int(elapsed / 0.3)
        if episode != hitEpisode {
            if hitEpisode >= 0, !hitResolved { hitFailures.append(hitLabel + ": no completed contact") }
            hitEpisode = episode; hitAccumulator = 0; hitFired = false; hitFrame = 0; endpointFrame = nil; hitResolved = false
            let kind = weapons[episode % weapons.count], profile = profiles[(episode / weapons.count) % profiles.count]
            hitLabel = kind + "/" + profile
            var shooter = ArenaTank(id: 1, name: "CONTACT", x: 42, y: 42, spawnSerial: 1, powerTime: 30,
                power: ["regular", "starman"].contains(kind) ? "" : kind, charges: 3, machineRounds: 180)
            if kind == "starman" || profile == "starman" { shooter.starmanTime = 30 }
            if profile == "speed" { shooter.speedTime = 30; shooter.speedStacks = 5 }
            if profile == "ghost" { shooter.ghostTime = 30 }
            var victim = ArenaTank(id: 2, name: "TARGET", x: kind == "starman" ? 75 : 78, y: 42, bot: true,
                spawnSerial: 1, cooldown: 999)
            if profile == "shield" { victim.shield = 30; victim.shieldCharges = 1 }
            hitArena = PracticeArena(seed: 42, name: "CONTACT", colorIndex: 0, botCount: 0, initialTanks: [shooter, victim])
        }
        let arena = hitArena!
        hitAccumulator += min(dt, 0.1)
        while hitAccumulator + 1e-9 >= 1 / 60 {
            arena.step(input: GameInput(fire: !hitFired && weapons[episode % weapons.count] != "starman"), dt: 1 / 60)
            hitFired = true; hitAccumulator = max(0, hitAccumulator - 1 / 60)
        }
        hitFrame += 1
        let visible = arena.presentationSnapshot(fraction: hitAccumulator * 60, now: elapsed)
        if !hitResolved, let effect = arena.snapshot.effects.first(where: { $0.contact != nil }), let contact = effect.contact,
           let body = visible.tanks.first(where: { $0.id == contact.target }) {
            if contact.projectileId > 0, let flight = arena.snapshot.effects.first(where: { $0.flight?.id == contact.projectileId })?.flight,
               let end = flight.points.last, let bullet = visible.bullets.first(where: { $0.id == flight.id }),
               hypot(bullet.x - end.x, bullet.y - end.y) < 1e-7, body.hp > 0,
               hypot(bullet.x - body.x, bullet.y - body.y) <= 17 + (flight.radius ?? 0) + 1e-7 { endpointFrame = endpointFrame ?? hitFrame }
            if contact.projectileId == 0, body.hp > 0 {
                let beam = visible.effects.contains { $0.kind == "laser" }
                let touching = contact.kind == "starman" && visible.tanks.contains { $0.id == effect.owner && hypot($0.x - body.x, $0.y - body.y) <= 34.0000001 }
                if beam || touching { endpointFrame = endpointFrame ?? hitFrame }
            }
            if visible.effects.contains(where: { $0.id == effect.id }) || body.hp <= 0 {
                if endpointFrame == nil || endpointFrame! >= hitFrame { hitFailures.append(hitLabel + ": damage before displayed contact") }
                hitChecks += 1; hitResolved = true
            }
        }
        return visible
    }

    func record(dt: Double, cpu: Double, simulation: Double, audio: Double, hud: Double,
                rendering: GameScene.RenderMetrics) {
        var motion = [0.0, 0.0, 0.0]
        if let pose = motionPose, let previous = previousMotionPose, dt > 0 {
            let velocity = (x: (pose.x - previous.x) / dt, y: (pose.y - previous.y) / dt)
            motion[0] = hypot(velocity.x, velocity.y)
            if let old = previousVelocity {
                let acceleration = (x: (velocity.x - old.x) / dt, y: (velocity.y - old.y) / dt)
                motion[1] = hypot(acceleration.x, acceleration.y)
                if let old = previousAcceleration {
                    motion[2] = hypot(acceleration.x - old.x, acceleration.y - old.y) / dt
                }
                previousAcceleration = acceleration
            }
            previousVelocity = velocity
        }
        previousMotionPose = motionPose
        if let event = pickupEvent {
            let key = "\(event.episode):\(event.stage)"
            if key != previousPickupEvent {
                if event.stage == "plain" {
                    FileHandle.standardOutput.write(Data("leqra pickup probe: \(event.power) at \(elapsed)s\n".utf8))
                }
                pickupEvents.append(["power": event.power, "stage": event.stage, "elapsed": elapsed,
                    "cpuMS": cpu * 1000, "renderMS": rendering.totalSeconds * 1000,
                    "tanksMS": rendering.tankSeconds * 1000, "textureCreations": rendering.textureCreations,
                    "audioMS": audio * 1000, "hudMS": hud * 1000, "nextFrameMS": 0.0,
                    "cpuMaxMS": cpu * 1000, "frameMaxMS": dt * 1000, "hudMaxMS": hud * 1000])
                previousPickupEvent = key
            } else if !pickupEvents.isEmpty, pickupEvents[pickupEvents.count - 1]["nextFrameMS"] as? Double == 0 {
                pickupEvents[pickupEvents.count - 1]["nextFrameMS"] = dt * 1000
            }
            if !pickupEvents.isEmpty {
                let index = pickupEvents.count - 1
                pickupEvents[index]["cpuMaxMS"] = max(pickupEvents[index]["cpuMaxMS"] as? Double ?? 0, cpu * 1000)
                pickupEvents[index]["frameMaxMS"] = max(pickupEvents[index]["frameMaxMS"] as? Double ?? 0, dt * 1000)
                pickupEvents[index]["hudMaxMS"] = max(pickupEvents[index]["hudMaxMS"] as? Double ?? 0, hud * 1000)
            }
        }
        if firstShotProbe {
            let visible = weapon == "laser" ? rendering.effects : rendering.bullets
            if visible > 0 && previousBulletCount == 0 {
                firstShots.append(["elapsed": elapsed, "cpuMS": cpu * 1000, "renderMS": rendering.totalSeconds * 1000,
                    "bulletsMS": rendering.bulletSeconds * 1000, "projectileCreations": rendering.projectileCreations,
                    "textureCreations": rendering.textureCreations, "simulationMS": simulation * 1000,
                    "audioMS": audio * 1000, "hudMS": hud * 1000, "nextFrameMS": 0.0])
            } else if previousBulletCount > 0, !firstShots.isEmpty,
                      firstShots[firstShots.count - 1]["nextFrameMS"] as? Double == 0 {
                firstShots[firstShots.count - 1]["nextFrameMS"] = dt * 1000
            }
            previousBulletCount = visible
        }
        guard !reported, elapsed > 3 else { return }
        if elapsed <= duration + 3 {
            samples.append([dt, cpu, simulation, audio, hud, rendering.totalSeconds,
                            rendering.mapSeconds, rendering.tankSeconds, rendering.guideSeconds,
                            rendering.bulletSeconds, rendering.effectSeconds,
                            rendering.mapRasterSeconds, rendering.mapInstallSeconds] + motion)
            projectileCreations += rendering.projectileCreations
            effectCreations += rendering.effectCreations
            mapRebuilds += rendering.mapRebuilds
            return
        }
        reported = true
        guard !samples.isEmpty else { return }
        func distribution(_ column: Int, multiplier: Double = 1000) -> [String: Double] {
            let values = samples.map { $0[column] * multiplier }.sorted()
            func quantile(_ fraction: Double) -> Double { values[min(values.count - 1, Int(Double(values.count - 1) * fraction))] }
            return ["mean": values.reduce(0, +) / Double(values.count), "p50": quantile(0.5),
                    "p95": quantile(0.95), "p99": quantile(0.99), "max": values.last!]
        }
        var report: [String: Any] = ["weapon": weapon, "bullets": count, "pan": pans, "buffs": buffs.sorted(),
            "frames": samples.count, "fps": Double(samples.count) / samples.reduce(0) { $0 + $1[0] },
            "frameMS": distribution(0), "cpuMS": distribution(1), "simulationMS": distribution(2),
            "audioMS": distribution(3), "hudMS": distribution(4), "renderMS": distribution(5),
            "mapMS": distribution(6), "tanksMS": distribution(7), "guideMS": distribution(8),
            "bulletsMS": distribution(9), "effectsMS": distribution(10),
            "mapRasterMS": distribution(11), "mapInstallMS": distribution(12),
            "projectileCreations": projectileCreations, "effectCreations": effectCreations, "mapRebuilds": mapRebuilds]
        if let motionMode {
            report["motion"] = motionMode
            report["speedWorldPerSecond"] = distribution(13, multiplier: 1)
            report["accelerationWorldPerSecondSquared"] = distribution(14, multiplier: 1)
            report["jerkWorldPerSecondCubed"] = distribution(15, multiplier: 1)
        }
        if firstShotProbe { report["firstShots"] = firstShots }
        if hitMatrixProbe { report["contactChecks"] = hitChecks; report["contactFailures"] = hitFailures }
        if pickupMatrixProbe { report["pickupEvents"] = pickupEvents; report["fixed"] = world != nil }
        if ammoRefillProbe { report["ammoRefillChecks"] = ammoChecks; report["ammoRefillFailures"] = ammoFailures; report["fixed"] = world != nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            if pickupMatrixProbe {
                let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("leqra-profile.json")
                try data.write(to: destination, options: .atomic)
                FileHandle.standardOutput.write(Data("leqra performance report saved\n".utf8))
            } else if let json = String(data: data, encoding: .utf8) {
                FileHandle.standardOutput.write(Data(("leqra performance: " + json + "\n").utf8))
            }
        } catch {
            let invalid = report.filter { !JSONSerialization.isValidJSONObject([$0.key: $0.value]) }.map(\.key)
            FileHandle.standardOutput.write(Data("leqra performance report error: \(error), fields \(invalid)\n".utf8))
        }
    }
}
