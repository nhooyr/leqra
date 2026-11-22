import XCTest

@testable import leqraCore

final class PilotColorTests: XCTestCase {
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
