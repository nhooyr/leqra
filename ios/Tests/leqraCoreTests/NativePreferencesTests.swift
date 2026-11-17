import Foundation
import XCTest
@testable import leqraCore

final class NativePreferencesTests: XCTestCase {
    func testResetRemovesEveryAppSettingWithoutTouchingAnotherDomain() {
        let name = "reset-settings-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for key in NativePreferences.appSettingKeys { defaults.set("changed", forKey: key) }
        defaults.set("system-owned", forKey: "NSUnrelatedSetting")
        NativePreferences.resetAppSettings(in: defaults)
        for key in NativePreferences.appSettingKeys { XCTAssertNil(defaults.persistentDomain(forName: name)?[key], key) }
        XCTAssertEqual(defaults.string(forKey: "NSUnrelatedSetting"), "system-owned")
    }

    func testProductionUsesOrdinaryStoreAndTestsKeepSeparatePersistentPreferences() {
        let baselineName = "preferences-baseline-" + UUID().uuidString
        let baseline = UserDefaults(suiteName: baselineName)!
        let first = "first-" + UUID().uuidString, second = "second-" + UUID().uuidString
        defer {
            baseline.removePersistentDomain(forName: baselineName)
            baseline.removePersistentDomain(forName: NativePreferences.domain(first))
            baseline.removePersistentDomain(forName: NativePreferences.domain(second))
        }
        baseline.set("PLAYER", forKey: "callsign")
        XCTAssertTrue(NativePreferences.applicationStore(arguments: [], standard: baseline) === baseline)
        let test = NativePreferences.applicationStore(arguments: ["--public-session-test-namespace", first], standard: baseline)
        test.set("TEST", forKey: "callsign")
        let cold = NativePreferences.applicationStore(arguments: ["--public-session-test-namespace", first], standard: baseline)
        XCTAssertEqual(cold.string(forKey: "callsign"), "TEST")
        XCTAssertEqual(baseline.string(forKey: "callsign"), "PLAYER")
        let other = NativePreferences.applicationStore(arguments: ["--public-session-test-namespace", second], standard: baseline)
        XCTAssertNil(other.string(forKey: "callsign"))
        _ = NativePreferences.applicationStore(arguments: ["--public-session-test-namespace", first, "--reset-public-session-test-store"], standard: baseline)
        XCTAssertNil(test.string(forKey: "callsign"))
        XCTAssertEqual(baseline.string(forKey: "callsign"), "PLAYER")
    }

    func testLaunchArgumentOverridesSurviveIsolationWithoutBecomingStoredValues() {
        let baselineName = "preferences-args-" + UUID().uuidString, namespace = UUID().uuidString
        let baseline = UserDefaults(suiteName: baselineName)!
        let originalArguments = baseline.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            baseline.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
            baseline.removePersistentDomain(forName: baselineName)
            baseline.removePersistentDomain(forName: NativePreferences.domain(namespace))
        }
        baseline.setVolatileDomain(["serverURL": "http://127.0.0.1:18224"], forName: UserDefaults.argumentDomain)
        let test = NativePreferences.applicationStore(arguments: ["--public-session-test-namespace", namespace], standard: baseline)
        XCTAssertEqual(test.string(forKey: "serverURL"), "http://127.0.0.1:18224")
        XCTAssertNil(test.persistentDomain(forName: NativePreferences.domain(namespace))?["serverURL"])
    }
}
