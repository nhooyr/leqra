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
    private var motionTank: ArenaTank?
    private let motionPresenter = TankMotionPresenter()
    private var motionTick: UInt64 = 0
    private var motionAccumulator = 0.0
    private var motionPose: ArenaTank?
    private var previousMotionPose: ArenaTank?
    private var previousVelocity: (x: Double, y: Double)?
    private var previousAcceleration: (x: Double, y: Double)?
    let maze = InfiniteMaze(seed: 42)
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
            tank.starmanTime = 8; tank.ghostTime = 8; tank.invulnerable = 8
            if buffs.contains("shield") || weapon == "shield" { tank.shield = 15; tank.shieldCharges = 5 }
            if buffs.contains("speed") || weapon == "speed" { tank.speedTime = 15; tank.speedStacks = 5 }
            tank.track = time * 30; tank.charges = 3; tank.machineRounds = 180
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
        return value
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
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write(Data(("leqra performance: " + json + "\n").utf8))
        }
    }
}
