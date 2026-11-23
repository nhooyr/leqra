import XCTest

@testable import leqraCore

final class PilotColorTests: XCTestCase {
    func testAuthoritativePilotColorsChangeOnlyWhenServerPaintChanges() {
        XCTAssertEqual(GamePalette.changedPilotColor(previous: nil, current: 4), 4)
        XCTAssertEqual(GamePalette.changedPilotColor(previous: 4, current: 6), 6)
        XCTAssertEqual(GamePalette.changedPilotColor(previous: 7, current: 0), 0)
        XCTAssertNil(GamePalette.changedPilotColor(previous: 6, current: 6))
        XCTAssertNil(GamePalette.changedPilotColor(previous: 6, current: nil))
        XCTAssertNil(GamePalette.changedPilotColor(previous: 6, current: -1))
        XCTAssertNil(GamePalette.changedPilotColor(previous: 6, current: 8))
    }
    func testNewPilotColorAvoidsOldPaintOtherPilotAndBots() {
        let used = [1, 2, 3]
        let choices = (0..<4).map { pick in
            GamePalette.randomPilotColor(current: 0, avoiding: used, choose: { _ in pick })
        }
        XCTAssertEqual(Set(choices), Set([4, 5, 6, 7]))
    }
    func testFullPaletteKeepsCurrentColor() {
        XCTAssertEqual(GamePalette.randomPilotColor(current: 2, avoiding: Array(0..<8)), 2)
    }
}
