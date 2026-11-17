import Foundation
import XCTest
@testable import leqraCore

final class NativeControlBindingsTests: XCTestCase {
    func testBothLayoutsRouteToTheOneSelectedHardwareSeat() throws {
        let defaults = NativeControlBindings.defaults
        XCTAssertTrue(defaults.isValid)
        XCTAssertTrue(defaults.input(pressed: [26]).forward)
        XCTAssertTrue(defaults.input(pressed: [82]).forward)
        XCTAssertTrue(defaults.input(pressed: [20, 44]).fire)
        let remapped = try defaults.assigning(8, layout: 0, action: .forward)
        XCTAssertFalse(remapped.input(pressed: [26]).forward)
        XCTAssertTrue(remapped.input(pressed: [8]).forward)
        XCTAssertTrue(remapped.input(pressed: [82]).forward)
    }
    func testConflictsAndReservedKeysAreRejectedWithoutChangingBindings() throws {
        let defaults = NativeControlBindings.defaults
        XCTAssertThrowsError(try defaults.assigning(82, layout: 0, action: .forward)) { XCTAssertEqual($0 as? NativeBindingError, .duplicate) }
        for code in [9, 16, 19, 41, 43, 224, 226, 227, 228, 230, 231, 0, 10000] {
            XCTAssertThrowsError(try defaults.assigning(code, layout: 0, action: .forward)) { XCTAssertEqual($0 as? NativeBindingError, .reserved) }
        }
        XCTAssertEqual(try defaults.assigning(26, layout: 0, action: .forward), defaults)
        XCTAssertTrue(NativeControlBindings.validKey(225)); XCTAssertTrue(NativeControlBindings.validKey(229))
    }
    func testPreferencesPersistAndCorruptionDoesNotIntroduceConflicts() throws {
        let name = "native-controls-" + UUID().uuidString, store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        var preferences = NativeControlPreferences()
        preferences.bindings = try preferences.bindings.assigning(8, layout: 0, action: .forward)
        preferences.mouseAim = false; preferences.mouseFire = true; preferences.save(to: store)
        XCTAssertEqual(NativeControlPreferences.load(from: store), preferences)
        var invalid = preferences; invalid.bindings.layouts[1].fire = invalid.bindings.layouts[0].fire
        store.set(try JSONEncoder().encode(invalid), forKey: NativeControlPreferences.storageKey)
        XCTAssertEqual(NativeControlPreferences.load(from: store), NativeControlPreferences())
    }
}
