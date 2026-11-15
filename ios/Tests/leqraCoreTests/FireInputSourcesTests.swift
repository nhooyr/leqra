import XCTest
@testable import leqraCore

final class FireInputSourcesTests: XCTestCase {
    func testTouchAndKeyboardOverlapCannotInventGrenadePressesOrEndHeldFire() {
        for first in [FireInputSources.Source.touch, .keyboard] {
            let other: FireInputSources.Source = first == .touch ? .keyboard : .touch
            var sources = FireInputSources(), previous = false, edges: [Bool] = [], feedback = LocalFireFeedback()
            let empty = ArenaTank(id: 1, ammoUsed: 5)
            var now = 1.0, clicks = 0
            func update(_ source: FireInputSources.Source, _ down: Bool) {
                let held = sources.set(source, down: down)
                if held != previous { edges.append(held) }
                if feedback.setFire(held, tank: empty, generation: 1, now: now) { clicks += 1 }
                previous = held; now += 0.5
            }
            update(first, true)
            update(other, false) // A movement key reports no keyboard Fire.
            update(other, true)
            update(first, false)
            XCTAssertTrue(sources.held)
            XCTAssertEqual(edges, [true]); XCTAssertEqual(clicks, 1, "Overlapping sources never create another dry click or grenade press")
            update(other, false)
            XCTAssertEqual(edges, [true, false])
            update(first, true)
            XCTAssertEqual(edges, [true, false, true]); XCTAssertEqual(clicks, 2)
            sources.reset()
            XCTAssertFalse(sources.held)
        }
    }
}
