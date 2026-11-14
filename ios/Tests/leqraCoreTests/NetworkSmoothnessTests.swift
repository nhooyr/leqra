import Foundation
import XCTest
@testable import leqraCore

/// Ordered, deterministic WebSocket delivery exercises actual prediction and
/// presentation at 120 Hz, independently of emulator or Internet scheduling.
final class NetworkSmoothnessTests: XCTestCase {
    private struct Profile {
        var localChanges: [Double] = []
        var remoteChanges: [Double] = []
        var projectileChanges: [Double] = []
        var stalls = 0
        func p95(_ values: [Double]) -> Double { values.sorted()[Int(Double(values.count - 1) * 0.95)] }
    }

    private func profile(rtt: Double, jitter: Double, turning: Bool) throws -> Profile {
        let world = ArenaWorld(width: 20_000, height: 20_000, cols: 238, rows: 238)
        let move: RenderTimeline.Move = { TankMovement.step(tank: &$0, input: $1, dt: $2, walls: [], width: world.width, height: world.height) }
        let timeline = RenderTimeline(localID: 1, move: move)
        var local = ArenaTank(id: 1, name: "LOCAL", x: 10_000, y: 10_000, spawnSerial: 1,
                              speedTime: 60, speedStacks: 5)
        var inbound: [(at: Double, input: GameInput)] = [], outbound: [(at: Double, state: ArenaSnapshot)] = []
        var current = GameInput(), ackSteps: UInt32 = 0, lastInputAt = 0.0, lastStateAt = 0.0
        var serverTick = 0, sentCount = 0, stateCount = 0
        func variation(_ number: Int) -> Double {
            let pattern = [-1.0, 0.4, 0.9, -0.2, 0.7, -0.8, 0.1, 0.5]
            return pattern[number % pattern.count] * jitter
        }
        func state() -> ArenaSnapshot {
            var tank = local; tank.ack = current.seq; tank.ackSteps = ackSteps
            let time = Double(serverTick) / 60
            var value = ArenaSnapshot(tick: UInt64(600 + serverTick), tanks: [tank,
                ArenaTank(id: 2, x: 1000 + time * 384, y: 1000, spawnSerial: 1)])
            value.generation = 1; value.world = world
            value.bullets = [ArenaBullet(id: 1, x: 1000 + time * 846, y: 2000, vx: 846, life: 100)]
            return value
        }
        timeline.accept(state(), at: 0)
        var result = Profile(), previous: [Double]?, previousVelocity: [Double]?
        for frame in 1...1440 {
            let now = Double(frame) / 120
            if frame % 2 == 0 {
                while let next = inbound.first, next.at <= now + 1e-9 {
                    inbound.removeFirst()
                    if next.input.seq > current.seq { current = next.input; ackSteps = 0 }
                }
                serverTick += 1; ackSteps += 1
                move(&local, current, 1 / 60)
                if serverTick % 2 == 0 {
                    stateCount += 1
                    let delivery = max(lastStateAt + 1e-6, now + max(0, rtt / 2 + variation(stateCount)))
                    lastStateAt = delivery
                    outbound.append((delivery, state()))
                }
            }
            while let next = outbound.first, next.at <= now + 1e-9 {
                outbound.removeFirst(); timeline.accept(next.state, at: now)
            }
            let input = GameInput(forward: true, right: turning, touchAim: false)
            let rendered = try XCTUnwrap(timeline.render(dt: 1 / 120, input: input, now: now) { packet in
                sentCount += 1
                let delivery = max(lastInputAt + 1e-6, now + max(0, rtt / 2 + variation(sentCount + 3)))
                lastInputAt = delivery; inbound.append((delivery, packet))
            })
            let own = try XCTUnwrap(rendered.tanks.first { $0.id == 1 })
            let remote = try XCTUnwrap(rendered.tanks.first { $0.id == 2 })
            let bullet = try XCTUnwrap(rendered.bullets.first)
            let pose = [own.x, own.y, remote.x, bullet.x]
            if let previous {
                let velocity = [hypot(pose[0] - previous[0], pose[1] - previous[1]) * 120,
                                (pose[2] - previous[2]) * 120, (pose[3] - previous[3]) * 120]
                if let old = previousVelocity, now > 3 {
                    result.localChanges.append(abs(velocity[0] - old[0]))
                    result.remoteChanges.append(abs(velocity[1] - old[1]))
                    result.projectileChanges.append(abs(velocity[2] - old[2]))
                    if velocity[1] < 1 || velocity[2] < 1 { result.stalls += 1 }
                }
                previousVelocity = velocity
            }
            previous = pose
        }
        return result
    }

    func testOrderedLatencyProfilesKeepPredictionAndRemoteMotionContinuous() throws {
        for rtt in [0.001, 0.01, 0.025, 0.05, 0.15, 0.25, 0.4] {
            for jitter in [0.0, 0.012] {
                for turning in [false, true] {
                    let result = try profile(rtt: rtt, jitter: jitter, turning: turning)
                    print("Native network profile RTT=\(Int(rtt * 1000)) jitter=\(Int(jitter * 1000)) turn=\(turning): local p95/max=\(result.p95(result.localChanges))/\(result.localChanges.max()!), remote=\(result.p95(result.remoteChanges))/\(result.remoteChanges.max()!), projectile=\(result.p95(result.projectileChanges))/\(result.projectileChanges.max()!), stalls=\(result.stalls)")
                    XCTAssertEqual(result.stalls, 0)
                    XCTAssertLessThan(result.p95(result.localChanges), 26, "Packet jitter must not create the old83px/s camera speed pulses")
                    XCTAssertLessThan(result.localChanges.max()!, 30)
                    XCTAssertLessThan(result.remoteChanges.max()!, 2)
                    XCTAssertLessThan(result.projectileChanges.max()!, 4)
                }
            }
        }
    }
}
