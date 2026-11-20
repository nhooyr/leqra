import CryptoKit
import Foundation
import XCTest

@testable import leqraCore

final class CallsignCaseFoldTests: XCTestCase {
    func testCleanupAcceptsDecimalDigitsButRejectsOtherNumericCategories() {
        XCTAssertEqual(CallsignPolicy.clean("Tank²Ⅳ٣"), "Tank٣")
        XCTAssertEqual(CallsignPolicy.canonical("TANK²Ⅳ٣"), "tank٣")
    }

    func testGeneratedFoldMatchesEverySharedMappingAndCanonicalCase() throws {
        struct Fixture: Decodable {
            let scalarSHA256: String
            let ranges: [[Int]]
            let singles: [[Int]]
            let cases: [[String]]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("src/tests/fixtures/callsign-fold.json")))
        for pair in fixture.cases { XCTAssertEqual(CallsignCaseFold.fold(pair[0]), pair[1]) }
        for pair in fixture.singles {
            XCTAssertEqual(
                CallsignCaseFold.fold(String(Unicode.Scalar(pair[0])!)), String(Unicode.Scalar(pair[1])!))
        }
        for range in fixture.ranges {
            for scalar in stride(from: range[0], through: range[1], by: range[2]) {
                XCTAssertEqual(
                    CallsignCaseFold.fold(String(Unicode.Scalar(scalar)!)),
                    String(Unicode.Scalar(scalar + range[3])!))
            }
        }
        XCTAssertEqual(CallsignPolicy.canonical(" ςNOW "), CallsignPolicy.canonical("Σnow"))
        XCTAssertNotEqual(CallsignPolicy.canonical("ß"), CallsignPolicy.canonical("SS"))
        XCTAssertNotEqual(CallsignPolicy.canonical("ı"), CallsignPolicy.canonical("i"))
        XCTAssertNotEqual(CallsignPolicy.canonical("ﬃ"), CallsignPolicy.canonical("ffi"))
        var records = Data(capacity: (0x110000 - 0x800) * 8)
        for value in 0...0x10ffff {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let folded = try XCTUnwrap(CallsignCaseFold.fold(String(scalar)).unicodeScalars.first)
            for word in [UInt32(value), folded.value] {
                records.append(UInt8(truncatingIfNeeded: word >> 24))
                records.append(UInt8(truncatingIfNeeded: word >> 16))
                records.append(UInt8(truncatingIfNeeded: word >> 8))
                records.append(UInt8(truncatingIfNeeded: word))
            }
        }
        XCTAssertEqual(
            SHA256.hash(data: records).map { String(format: "%02x", $0) }.joined(), fixture.scalarSHA256)
    }
}
