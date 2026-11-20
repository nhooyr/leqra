import CoreGraphics
import Foundation
import XCTest

@testable import leqraCore

final class ScreenLabelLayoutTests: XCTestCase {
    func testOverlappingLocalNamesStayReadableAndInsideViewport() throws {
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 130)
        let preferred = CGRect(x: 120, y: 85, width: 190, height: 30)
        let result = ScreenLabelLayout.place(
            [
                .init(id: 2, frame: preferred, local: true),
                .init(id: 1, frame: preferred, local: true),
                .init(id: 3, frame: preferred),
            ], in: viewport)
        XCTAssertEqual(result.count, 3)
        let frames = try [1, 2, 3].map { try XCTUnwrap(result[$0]) }
        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(viewport.contains(frame))
            for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
        }
        XCTAssertEqual(frames[0], preferred, "P1 keeps the nearest label position")
    }

    func testLayoutIsStableAcrossSnapshotOrderAndKeepsSeparateNamesUnchanged() {
        let viewport = CGRect(x: 0, y: 0, width: 600, height: 400)
        let labels = [
            ScreenLabelLayout.Label(id: 3, frame: CGRect(x: 10, y: 20, width: 150, height: 30)),
            .init(id: 2, frame: CGRect(x: 320, y: 20, width: 150, height: 30), local: true),
        ]
        let result = ScreenLabelLayout.place(labels, in: viewport)
        XCTAssertEqual(result, ScreenLabelLayout.place(labels.reversed(), in: viewport))
        for label in labels { XCTAssertEqual(result[label.id], label.frame) }
    }

    func testCrowdedRosterKeepsAllEightLabelsSeparate() {
        let viewport = CGRect(x: 0, y: 0, width: 360, height: 260)
        let labels = (0..<8).map {
            ScreenLabelLayout.Label(
                id: $0,
                frame: CGRect(x: 90 + $0 % 2 * 12, y: 130 + $0 / 2 * 5, width: 170, height: 22), local: $0 < 2
            )
        }
        let result = ScreenLabelLayout.place(labels, in: viewport)
        let frames = Array(result.values)
        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(viewport.contains(frame))
            for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
        }
    }

    func testReportLabelLayoutCPU() throws {
        guard ProcessInfo.processInfo.environment["LEQRA_PROFILE_LABELS"] == "1" else {
            throw XCTSkip("Opt in to the screen label layout CPU benchmark.")
        }
        let viewport = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for crowded in [false, true] {
            let labels = (0..<24).map { index in
                ScreenLabelLayout.Label(
                    id: index,
                    frame: CGRect(
                        x: crowded ? 500 + index % 2 * 12 : index % 6 * 195,
                        y: crowded ? 350 + index / 2 * 5 : index / 6 * 185, width: 170, height: 22),
                    local: index < 2)
            }
            var samples: [Double] = []
            for run in 0..<220 {
                let started = ProcessInfo.processInfo.systemUptime
                for _ in 0..<20 {
                    XCTAssertEqual(ScreenLabelLayout.place(labels, in: viewport).count, labels.count)
                }
                if run >= 20 { samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000 / 20) }
            }
            samples.sort()
            print(
                "24 labels, crowded=\(crowded), CPU ms/frame p50=\(samples[100]) p95=\(samples[190]) p99=\(samples[198])"
            )
        }
    }
}
