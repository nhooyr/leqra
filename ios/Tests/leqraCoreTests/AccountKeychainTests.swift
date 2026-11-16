import Foundation
import XCTest
import leqraCore
@testable import leqraAccountStore

@MainActor
final class AccountKeychainTests: XCTestCase {
    private let base = URL(string: "https://leqra.test")!
    private func credential(_ letter: String, server: URL? = nil) throws -> PublicInfinitySession {
        try PublicInfinitySession(baseURL: server ?? base, publicToken: "p_" + String(repeating: letter, count: 43))
    }

    func testSavedCallsignsRetainIndependentKeysAcrossSelectionAndColdStart() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let first = try credential("A"), second = try credential("B")
        XCTAssertTrue(store.remember(first))
        XCTAssertTrue(store.saveCallsign("FIRST", credential: first))
        XCTAssertTrue(store.backup(second, seat: 0))
        XCTAssertEqual(store.session(for: base), first, "A pending new callsign must not select its key")
        XCTAssertTrue(store.saveCallsign("SECOND", credential: second))
        XCTAssertTrue(store.remember(second))
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.savedCallsigns(for: base).map(\.name), ["FIRST", "SECOND"])
        XCTAssertEqual(cold.savedCallsigns(for: base).first?.credential, first)
        XCTAssertTrue(cold.savedCallsigns(for: URL(string: "https://another.test")!).isEmpty)
        XCTAssertTrue(cold.remember(first))
        XCTAssertEqual(cold.savedCallsigns(for: base).count, 2)
        let rotated = try credential("C")
        XCTAssertTrue(cold.saveCallsign("first", credential: rotated))
        XCTAssertEqual(cold.savedCallsigns(for: base).filter { $0.name.lowercased() == "first" }.map(\.credential), [rotated])
    }

    func testPendingCallsignKeepsExactRetryCandidateWithoutReplacingHistory() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let old = try credential("A"), candidate = try credential("B")
        XCTAssertTrue(store.remember(old)); XCTAssertTrue(store.saveCallsign("OLD", credential: old))
        let pending = PendingCallsignAccount(name: "NEW", credential: candidate, previous: old)
        XCTAssertTrue(store.savePendingCallsign(pending, seat: 0))
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.pendingCallsign(for: base, seat: 0), pending)
        XCTAssertEqual(cold.session(for: base), old)
        XCTAssertEqual(cold.savedCallsigns(for: base).map(\.name), ["OLD"])
        XCTAssertTrue(cold.registrationCandidates(for: base, seat: 0).contains(candidate))
        XCTAssertTrue(cold.clearPendingCallsign(for: base, seat: 0))
        XCTAssertNil(cold.pendingCallsign(for: base, seat: 0))
    }

    func testReleasePurgesOnlyMatchingHistoryAndPendingCredentials() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let released = try credential("A"), other = try credential("B"), candidate = try credential("C")
        XCTAssertTrue(store.remember(released, seat: 0)); XCTAssertTrue(store.remember(other, seat: 1))
        XCTAssertTrue(store.saveCallsign("OLD", credential: released)); XCTAssertTrue(store.saveCallsign("OTHER", credential: other))
        XCTAssertTrue(store.backup(released, seat: 0))
        XCTAssertTrue(store.savePendingCallsign(.init(name: "NEW", credential: candidate, previous: released), seat: 0))
        XCTAssertTrue(store.rememberPendingKey(.init(previous: released, replacement: candidate), seat: 0))
        XCTAssertTrue(store.forgetAccount(released))
        XCTAssertNil(store.session(for: base, seat: 0))
        XCTAssertEqual(store.session(for: base, seat: 1), other)
        XCTAssertEqual(store.savedCallsigns(for: base).map(\.name), ["OTHER"])
        XCTAssertEqual(store.pendingCallsign(for: base, seat: 0), PendingCallsignAccount(name: "NEW", credential: candidate, previous: nil))
        XCTAssertNil(store.pendingKey(for: base, seat: 0))
        XCTAssertTrue(store.registrationCandidates(for: base, seat: 0).contains(candidate))
        XCTAssertFalse(store.registrationCandidates(for: base, seat: 0).contains(released))
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.savedCallsigns(for: base).map(\.name), ["OTHER"])
    }

    func testReleaseReplacementKeepsItsExactCallsignForTheNextRegistration() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let old = try credential("A"), replacement = try credential("B")
        XCTAssertTrue(store.remember(old)); XCTAssertTrue(store.saveCallsign("OLD", credential: old))
        XCTAssertTrue(store.backup(replacement, seat: 0))
        XCTAssertTrue(store.forgetAccount(old))
        XCTAssertTrue(store.rememberNew(replacement, seat: 0))
        let name = "pilot#ABCDEF"
        XCTAssertTrue(store.savePendingCallsign(.init(name: name, credential: replacement, previous: replacement), seat: 0))
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertTrue(cold.registrationPending(for: base, seat: 0))
        XCTAssertEqual(cold.session(for: base), replacement)
        XCTAssertEqual(cold.pendingCallsign(for: base, seat: 0)?.name, name)
    }

    func testMalformedStoredCredentialsStillProtectLegacyNamesFromMigration() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertFalse(store.hasStoredCredential(for: base, seat: 0))
        XCTAssertTrue(store.remember(try credential("A"), seat: 0))
        let account = try XCTUnwrap(io.values.keys.first { $0.hasPrefix("identity-") })
        io.values[account] = Data("malformed saved credential".utf8)
        XCTAssertNil(store.session(for: base, seat: 0))
        XCTAssertTrue(store.hasStoredCredential(for: base, seat: 0))
        XCTAssertFalse(store.hasStoredCredential(for: base, seat: 1))
        XCTAssertFalse(store.hasStoredCredential(for: URL(string: "https://other.test")!, seat: 0))
    }

    func testP1AndP2CredentialsAndOriginsStayIndependent() throws {
        let io = MemoryAccountKeychain()
        let tested = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let primary = try credential("A"), local = try credential("B")
        XCTAssertTrue(tested.remember(primary, seat: 0)); XCTAssertTrue(tested.remember(local, seat: 1))
        XCTAssertEqual(tested.session(for: base, seat: 0), primary)
        XCTAssertEqual(tested.session(for: base, seat: 1), local)
        XCTAssertNil(tested.session(for: URL(string: "http://leqra.test")!, seat: 1))
        XCTAssertNil(tested.session(for: URL(string: "https://other.test")!, seat: 0))
        XCTAssertTrue(tested.forget(base, ifMatching: primary.publicToken, seat: 1))
        XCTAssertEqual(tested.session(for: base, seat: 1), local, "P1's old event cannot erase P2")
    }

    func testFreshCandidateSurvivesImportAndStaleWelcomeUntilExplicitRecovery() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let candidate = try credential("C"), imported = try credential("B")
        XCTAssertTrue(store.rememberNew(candidate, seat: 1))
        XCTAssertTrue(store.registrationPending(for: base, seat: 1))
        // The candidate's server join may commit after this import.
        XCTAssertTrue(store.remember(imported, seat: 1))
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
        XCTAssertFalse(store.confirm(candidate, requested: candidate.publicToken, seat: 1))
        XCTAssertEqual(store.session(for: base, seat: 1), imported)
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.registrationCandidates(for: base, seat: 1), [candidate])
        // Only a deliberate, validated selection makes this backup redundant.
        XCTAssertTrue(cold.remember(candidate, seat: 1))
        XCTAssertEqual(cold.session(for: base, seat: 1), candidate)
        XCTAssertTrue(cold.registrationCandidates(for: base, seat: 1).isEmpty)
    }

    func testFreshPrivateResumeCanConfirmRecoveredKeyWithoutLosingUnusedCandidate() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let candidate = try credential("C"), recovered = try credential("B")
        XCTAssertTrue(store.rememberNew(candidate, seat: 1))
        XCTAssertTrue(store.confirm(recovered, requested: candidate.publicToken, seat: 1))
        XCTAssertEqual(store.session(for: base, seat: 1), recovered)
        XCTAssertFalse(store.registrationPending(for: base, seat: 1))
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
    }

    func testRotationPendingRecordsAndColdLocalIntentAreScopedToEachSeat() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let primary = try credential("A"), local = try credential("B")
        let primaryNext = try credential("D"), localNext = try credential("E")
        XCTAssertTrue(store.remember(primary, seat: 0)); XCTAssertTrue(store.remember(local, seat: 1))
        XCTAssertTrue(store.activate(base, local: true))
        let p1 = PendingAccountKey(previous: primary, replacement: primaryNext), p2 = PendingAccountKey(previous: local, replacement: localNext)
        XCTAssertTrue(store.rememberPendingKey(p1, seat: 0)); XCTAssertTrue(store.rememberPendingKey(p2, seat: 1))
        XCTAssertTrue(store.clearPendingKey(base, ifMatching: primaryNext.publicToken, seat: 1))
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.pendingKey(for: base, seat: 0), p1); XCTAssertEqual(cold.pendingKey(for: base, seat: 1), p2)
        XCTAssertTrue(cold.activeLocal); XCTAssertEqual(cold.activeServer, base)
        XCTAssertTrue(cold.remember(localNext, seat: 1))
        XCTAssertEqual(cold.session(for: base, seat: 0), primary)
        XCTAssertTrue(cold.forget(base, ifMatching: local.publicToken, seat: 1))
        XCTAssertEqual(cold.session(for: base, seat: 1), localNext, "A late revocation cannot delete the replacement")
        XCTAssertTrue(cold.activate(base, local: false))
        XCTAssertFalse(cold.activeLocal); XCTAssertEqual(cold.activeServer, base)
        XCTAssertEqual(cold.pendingKey(for: base, seat: 0), p1)
    }

    func testCandidateBackupIsWrittenBeforeSelectedCredentialAndSurvivesWriteFailure() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        io.failSelectedLocalWrites = true
        let candidate = try credential("C")
        XCTAssertFalse(store.rememberNew(candidate, seat: 1))
        XCTAssertNil(store.session(for: base, seat: 1))
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
        XCTAssertTrue(io.writes.first?.hasPrefix("registrations-local-identity-") == true)
    }

    func testLegacyPrimaryIntentAndCredentialsRemainReadableWithoutSelectingP2() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let primary = try credential("A")
        XCTAssertTrue(store.remember(primary))
        io.values["active-origin"] = Data("https://leqra.test".utf8)
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.activeServer, base); XCTAssertFalse(cold.activeLocal)
        XCTAssertEqual(cold.session(for: base), primary); XCTAssertNil(cold.session(for: base, seat: 1))
    }
}

@MainActor
private final class MemoryAccountKeychain: AccountKeychainIO {
    var values: [String: Data] = [:]
    var writes: [String] = []
    var failSelectedLocalWrites = false
    func read(account: String) -> Data? { values[account] }
    func write(_ data: Data, account: String) -> Bool {
        writes.append(account)
        if failSelectedLocalWrites && account.hasPrefix("local-identity-") { return false }
        values[account] = data; return true
    }
    func delete(account: String?) -> Bool {
        if let account { values.removeValue(forKey: account) } else { values.removeAll() }
        return true
    }
}
