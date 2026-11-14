import Foundation
import XCTest
@testable import leqraCore

final class CallsignGenerationTests: XCTestCase {
    private let server = URL(string: "https://leqra.test")!
    func testFreshDefaultsAreIndependentPersistedAndPendingUntilClaimed() throws {
        let memory = MemoryCallsignPreferences(), store = CallsignDraftStore(preferences: memory)
        let primary = store.name(seat: 0), second = store.name(seat: 1)
        XCTAssertNotEqual(primary, second)
        for value in [primary, second] {
            XCTAssertEqual(value.count, 12)
            XCTAssertNotNil(value.range(of: #"^pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$"#, options: .regularExpression))
        }
        let cold = CallsignDraftStore(preferences: memory)
        XCTAssertEqual(cold.name(seat: 0), primary); XCTAssertEqual(cold.name(seat: 1), second)
        XCTAssertTrue(cold.automaticPending(seat: 0)); XCTAssertTrue(cold.automaticPending(seat: 1))
        let request = try cold.begin(server: server, seats: [0, 1])
        XCTAssertEqual(try store.begin(server: server, seats: [1, 0]).requestId, request.requestId)
        XCTAssertGreaterThan(memory.flushes, 0)
        XCTAssertTrue(cold.apply("pilot-abcdefghij", seat: 0, attempt: request))
        XCTAssertFalse(cold.automaticPending(seat: 0)); XCTAssertTrue(cold.automaticPending(seat: 1))
        XCTAssertTrue(cold.apply("pilot-klmnopqrst", seat: 1, attempt: request))
        cold.complete(request)
        XCTAssertNotEqual(try cold.begin(server: server, seats: [0]).requestId, request.requestId)
    }

    func testExistingNamesAndLateUserEditsAreNeverOverwritten() throws {
        let memory = MemoryCallsignPreferences()
        memory.values["callsign"] = "Bot LEGACY"
        memory.values["localCallsign"] = "SAVED P2"
        let store = CallsignDraftStore(preferences: memory)
        XCTAssertEqual(store.name(seat: 0), "Bot LEGACY"); XCTAssertEqual(store.name(seat: 1), "SAVED P2")
        XCTAssertFalse(store.automaticPending(seat: 0)); XCTAssertFalse(store.automaticPending(seat: 1))
        let old = try store.begin(server: server, seats: [0, 1])
        store.edited("OTHER", seat: 0); store.edited("Bot LEGACY", seat: 0)
        XCTAssertFalse(store.apply("SERVER RESULT", seat: 0, attempt: old), "Editing away and back still invalidates a late response")
        XCTAssertTrue(store.apply("VALID P2", seat: 1, attempt: old))
        memory.writable = false
        XCTAssertThrowsError(try store.begin(server: server, seats: [0]))
        XCTAssertThrowsError(try store.begin(server: server, seats: [0]), "An in-memory UUID from a failed flush is still unsafe to send")
    }

    func testOnlyCanonicalBotNamespaceIsReservedForHumans() {
        for name in ["Bot RUST", " bOt  17 ", "BOT", "Bot !RUST", "Bot 7 - Godlike", "B\u{0301}ot RUST", "B\u{034f}ot RUST"] { XCTAssertTrue(CallsignPolicy.reservedForBots(name), name) }
        for name in ["Botanist", "BotRUST", "Bot-RUST", "Bot\tRUST", "RUST", "GODLIKE N", "godlike-n", "Godlike Bot 7"] { XCTAssertFalse(CallsignPolicy.reservedForBots(name), name) }
        XCTAssertEqual(CallsignPolicy.displayName("RUST", bot: true), "Bot Rust")
        XCTAssertEqual(CallsignPolicy.displayName("BOT RUST", bot: true), "Bot Rust")
        XCTAssertEqual(CallsignPolicy.displayName("RUST", bot: false), "RUST")
        XCTAssertEqual(CallsignPolicy.displayName("Bot 7", bot: true), "Bot 7")
        XCTAssertEqual(CallsignPolicy.displayName("Bot 7 - Godlike", bot: true), "Bot 7 - Godlike")
        XCTAssertEqual(CallsignPolicy.displayName("Godlike Bot 7", bot: true), "Bot Godlike Bot 7")
        XCTAssertEqual(CallsignPolicy.displayName("Godlike Bot 7", bot: false), "Godlike Bot 7")
        XCTAssertEqual(CallsignPolicy.displayName("SNOW FOX", bot: false), "SNOW FOX")
        XCTAssertEqual(CallsignPolicy.displayName("VAPOR NOVA", bot: true), "Bot Vapor Nova")
        XCTAssertEqual(CallsignPolicy.clean("pilot#BDF3XZ"), "pilot#BDF3XZ")
        for name in ["pilot#BDF3XZ", "pilot#ABCD29", "pilot-abcdefghij"] { XCTAssertTrue(CallsignPolicy.isGenerated(name), name) }
        for name in ["pilot#ABCIO1", "pilot#abcdef", "pilot#ABCDEFG", "pilot-ABCDEF"] { XCTAssertFalse(CallsignPolicy.isGenerated(name), name) }
    }

    func testPreviouslySavedGeneratedNamesAreNotReplacedByTheNewFormat() {
        let memory = MemoryCallsignPreferences()
        memory.values["callsign"] = "pilot-abcdefghij"; memory.values["localCallsign"] = "pilot-klmnopqrst"
        let store = CallsignDraftStore(preferences: memory)
        XCTAssertEqual(store.name(seat: 0), "pilot-abcdefghij"); XCTAssertEqual(store.name(seat: 1), "pilot-klmnopqrst")
        XCTAssertFalse(store.automaticPending(seat: 0)); XCTAssertFalse(store.automaticPending(seat: 1))
    }

    func testAnEditedSeatAndManualRequestDoNotLoseTheOtherSeatsRetryID() throws {
        let memory = MemoryCallsignPreferences(), store = CallsignDraftStore(preferences: memory)
        let pair = try store.begin(server: server, seats: [0, 1])
        store.edited("MY EDIT", seat: 0)
        let secondOnly = try store.begin(server: server, seats: [1])
        XCTAssertEqual(secondOnly.requestId, pair.requestId)
        let newPrimary = try store.begin(server: server, seats: [0])
        XCTAssertNotEqual(newPrimary.requestId, pair.requestId)
        store.complete(newPrimary)
        XCTAssertEqual(try store.begin(server: server, seats: [1]).requestId, pair.requestId)
    }

    func testOfflineRepairKeepsTheRequestIdentityUntilItsServerClaimCompletes() throws {
        let memory = MemoryCallsignPreferences(), store = CallsignDraftStore(preferences: memory)
        memory.values["callsign"] = "Bot LEGACY"
        let attempt = try store.begin(server: server, seats: [0])
        let provisional = try XCTUnwrap(store.provisionalName(seat: 0, attempt: attempt))
        XCTAssertFalse(CallsignPolicy.reservedForBots(provisional)); XCTAssertEqual(provisional.count, 12)
        XCTAssertTrue(store.automaticPending(seat: 0))
        store.editorChanged(from: provisional, to: provisional, seat: 0)
        XCTAssertTrue(store.automaticPending(seat: 0), "Blur/save of the unchanged provisional name cannot cancel its online claim")
        let retry = try store.begin(server: server, seats: [0])
        XCTAssertEqual(retry.requestId, attempt.requestId)
        XCTAssertFalse(store.apply("LATE OLD", seat: 0, attempt: attempt))
        XCTAssertTrue(store.apply("SERVER CLAIM", seat: 0, attempt: retry))
        XCTAssertFalse(store.automaticPending(seat: 0))
    }

    func testAReservedEditorDraftInvalidatesRetriesWithoutOverwritingTheLastSavedName() throws {
        let memory = MemoryCallsignPreferences(), store = CallsignDraftStore(preferences: memory)
        store.edited("SAVED PILOT", seat: 0)
        let pending = try store.begin(server: server, seats: [0])
        store.editorChanged(from: "SAVED PILOT", to: "Bot BAD DRAFT", seat: 0)
        XCTAssertEqual(store.name(seat: 0), "SAVED PILOT")
        XCTAssertFalse(store.apply("STALE GENERATED", seat: 0, attempt: pending))
        XCTAssertFalse(store.automaticPending(seat: 0))
    }

    @MainActor func testLiveGenerationIsIdempotentAndSupportsAnIndependentSecondSeat() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else { throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable generation-enabled backend.") }
        let client = NetworkClient(), request = UUID()
        func key() -> String { "p_" + Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let accounts = [(seat: 0, publicToken: key()), (seat: 1, publicToken: key())]
        let first = try await client.generateCallsigns(baseURL: base, requestId: request, accounts: accounts)
        let retry = try await client.generateCallsigns(baseURL: base, requestId: request, accounts: accounts)
        XCTAssertEqual(first, retry); XCTAssertEqual(first.map(\.seat), [0, 1]); XCTAssertNotEqual(first[0].name, first[1].name)
        for account in accounts {
            let info = try await client.fetchAccountInfo(baseURL: base, publicToken: account.publicToken)
            XCTAssertEqual(info.names, [try XCTUnwrap(first.first { $0.seat == account.seat }).name])
        }
        let fresh = try await client.generateCallsigns(baseURL: base, requestId: UUID(), accounts: [accounts[1]])
        XCTAssertEqual(fresh.first?.seat, 1); XCTAssertNotEqual(fresh.first?.name, first[1].name)
    }
}

private final class MemoryCallsignPreferences: CallsignPreferences {
    var values: [String: Any] = [:]
    var writable = true
    var flushes = 0
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    func synchronize() -> Bool { flushes += 1; return writable }
}
