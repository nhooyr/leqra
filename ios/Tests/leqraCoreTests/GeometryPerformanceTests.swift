import Foundation
import XCTest
@testable import leqraCore

/// Opt-in release-build CPU evidence; this is not a device frame-rate test.
final class GeometryPerformanceTests: XCTestCase {
    private struct Query { let x, y, dx, dy: Double }
    func testReportGeometryWorkloads() throws {
        guard ProcessInfo.processInfo.environment["LEQRA_PROFILE_GEOMETRY"] == "1" else {
            throw XCTSkip("Opt in to the geometry CPU benchmark.")
        }
        var rules = RoomRules()
        rules.mapSize = "ultrawide"
        let fixed = InfiniteMaze(world: FixedArena(rules: rules, name: "PERF", colorIndex: 0, botCount: 0, seed: 42).world)
        for (name, maze) in [("fixed", fixed), ("infinity", InfiniteMaze(seed: 42))] {
            var queries: [Query] = []
            for index in 0..<1024 {
                let x: Double = 42.0 + Double(index % 21) * 83.25
                let y: Double = 42.0 + Double(index % 11) * 83.5
                let dx: Double = Double(index % 19 - 9) * 15.25
                let dy: Double = Double(index % 17 - 8) * 13.75
                queries.append(Query(x: x, y: y, dx: dx, dy: dy))
            }
            for operation in ["ray", "launch", "muzzle"] {
                var samples: [Double] = [], checksum: UInt64 = 0
                for sample in 0..<9 {
                    let start = ProcessInfo.processInfo.systemUptime
                    for index in 0..<16384 {
                        let q = queries[index % queries.count]
                        let value: Double
                        switch operation {
                        case "ray": value = maze.rayHit(x: q.x, y: q.y, dx: q.dx, dy: q.dy, radius: 3.5)?.fraction ?? -1
                        case "launch": value = maze.launchRay(x: q.x, y: q.y, angle: q.dx / 40, kind: "regular", radius: 3.5)?.x ?? -1
                        default:
                            var tank = ArenaTank(id: 1, x: q.x, y: q.y, angle: q.dx / 40)
                            tank.ghostTime = 10
                            value = MuzzlePresentation.retraction(tank: tank, maze: maze)
                        }
                        checksum = (checksum &* 31) &+ value.bitPattern
                    }
                    if sample >= 2 { samples.append((ProcessInfo.processInfo.systemUptime - start) * 1e9 / 16384) }
                }
                samples.sort()
                print("GEOMETRY \(name) \(operation) ns/query p50=\(samples[3]) p95=\(samples[6]) checksum=\(checksum)")
            }
        }
        var samples: [Double] = [], checksum = 0
        for sample in 0..<9 {
            let maze = InfiniteMaze(seed: 42)
            let start = ProcessInfo.processInfo.systemUptime
            for index in 0..<1024 {
                checksum += maze.walls(x0: Double(index * 672), y0: 0, x1: Double(index * 672 + 84), y1: 84).count
            }
            if sample >= 2 { samples.append((ProcessInfo.processInfo.systemUptime - start) * 1e9 / 1024) }
        }
        samples.sort()
        print("GEOMETRY cold-chunks ns/query p50=\(samples[3]) p95=\(samples[6]) checksum=\(checksum)")
    }
}
