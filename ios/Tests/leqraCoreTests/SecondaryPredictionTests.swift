import XCTest

@testable import leqraCore

final class SecondaryPredictionTests: XCTestCase {
    private func frame(
        tick: UInt64 = 0, x1: Double = 100, x2: Double = 500,
        ack1: UInt64 = 0, ack2: UInt64 = 0, steps2: UInt32 = 0, hp2: Int = 1, spawn2: Int = 1
    ) -> ArenaSnapshot {
        ArenaSnapshot(
            tick: tick,
            tanks: [
                ArenaTank(id: 1, name: "PRIMARY", x: x1, ack: ack1, ackSteps: 1, spawnSerial: 1),
                ArenaTank(
                    id: 2, name: "WING", x: x2, hp: hp2, ack: ack2, ackSteps: steps2, spawnSerial: spawn2),
            ])
    }
    private func timeline(paired: Bool = true) -> RenderTimeline {
        RenderTimeline(localID: 1, secondaryLocalID: paired ? 2 : nil) { tank, input, dt in
            if input.forward { tank.x += dt * 60 }
            if input.reverse { tank.x -= dt * 60 }
        }
    }
    func testTwoPilotsPredictAndAcknowledgeIndependentInputHistories() throws {
        let game = timeline()
        game.accept(frame(), at: 0)
        let edge = try XCTUnwrap(game.secondaryInputEdgePacket(GameInput(reverse: true, fire: true), now: 0))
        XCTAssertEqual(edge.seq, 1)
        var primary: [GameInput] = []
        var secondary: [GameInput] = []
        let shown = try XCTUnwrap(
            game.render(
                dt: 2 / 60, input: GameInput(forward: true), secondaryInput: GameInput(reverse: true),
                now: 2 / 60,
                sendSecondary: { secondary.append($0) }, send: { primary.append($0) }))
        XCTAssertEqual(primary.map(\.seq), [1, 2])
        XCTAssertEqual(secondary.map(\.seq), [2, 3])
        XCTAssertEqual(shown.tanks[0].x, 102, accuracy: 1e-9)
        XCTAssertEqual(shown.tanks[1].x, 498, accuracy: 1e-9)
        game.accept(frame(tick: 2, x1: 102, x2: 498, ack1: 2, ack2: 2, steps2: 2), at: 0.04)
        let settled = try XCTUnwrap(
            game.render(dt: 0, input: GameInput(), secondaryInput: GameInput(), now: 0.04) { _ in })
        XCTAssertEqual(settled.tanks[0].x, 102, accuracy: 1e-9)
        XCTAssertEqual(settled.tanks[1].x, 498, accuracy: 1e-9)
    }
    func testP2IsNotPredictedOrSentUntilExplicitlyEnabled() throws {
        let game = timeline(paired: false)
        game.accept(frame(), at: 0)
        var sent = 0
        let shown = try XCTUnwrap(
            game.render(
                dt: 1 / 60, input: GameInput(), secondaryInput: GameInput(forward: true), now: 1 / 60,
                sendSecondary: { _ in sent += 1 }, send: { _ in }))
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(shown.tanks[1].x, 500)
        game.setSecondaryLocalID(2)
        _ = game.render(
            dt: 1 / 60, input: GameInput(), secondaryInput: GameInput(forward: true), now: 2 / 60,
            sendSecondary: { _ in sent += 1 }, send: { _ in })
        XCTAssertEqual(sent, 1)
        game.setSecondaryLocalID(nil)
        XCTAssertNil(game.secondaryInputEdgePacket(GameInput(fire: true), now: 0.04))
        game.setSecondaryLocalID(2)
        XCTAssertEqual(game.secondaryInputEdgePacket(GameInput(fire: true), now: 0.04)?.seq, 2)
    }
    func testP2DeathRespawnAndSpectatingNeverReuseOldPrediction() throws {
        let game = timeline()
        game.accept(frame(), at: 0)
        _ = game.render(
            dt: 2 / 60, input: GameInput(forward: true), secondaryInput: GameInput(reverse: true), now: 2 / 60
        ) { _ in }
        game.accept(frame(tick: 2, x1: 102, x2: 900, ack1: 2, hp2: 0), at: 0.04)
        var shown = try XCTUnwrap(
            game.render(dt: 0, input: GameInput(), secondaryInput: GameInput(), now: 0.04) { _ in })
        XCTAssertEqual(shown.tanks[1].hp, 0)
        XCTAssertEqual(shown.tanks[1].x, 900)
        game.accept(frame(tick: 3, x1: 102, x2: 500, ack1: 2, spawn2: 2), at: 0.05)
        shown = try XCTUnwrap(
            game.render(dt: 0, input: GameInput(), secondaryInput: GameInput(), now: 0.05) { _ in })
        XCTAssertEqual(shown.tanks[1].x, 500)
        var observer = frame(tick: 4)
        observer.spectating = true
        game.accept(observer, at: 0.06)
        var secondaryPackets = 0
        shown = try XCTUnwrap(
            game.render(
                dt: 1 / 60, input: GameInput(forward: true), secondaryInput: GameInput(reverse: true),
                now: 0.07,
                sendSecondary: { _ in secondaryPackets += 1 }, send: { _ in }))
        XCTAssertEqual(secondaryPackets, 0)
        XCTAssertEqual(shown.tanks[1].x, 500)
    }
    func testFixedP2PredictsWhilePrimarySpectatesAndLateEnableUsesSamePolicy() throws {
        for initiallyPaired in [false, true] {
            let game = RenderTimeline(localID: -1, secondaryLocalID: initiallyPaired ? 2 : nil) {
                tank, input, dt in
                if input.reverse { tank.x -= dt * 60 }
            }
            var observed = frame()
            observed.spectating = true
            observed.world = ArenaWorld(width: 1000, height: 500, cols: 12, rows: 6)
            game.accept(observed, at: 0)
            if !initiallyPaired { game.setSecondaryLocalID(2) }
            XCTAssertNotNil(game.secondaryInputEdgePacket(GameInput(fire: true), now: 0))
            var p1: [GameInput] = []
            var p2: [GameInput] = []
            let shown = try XCTUnwrap(
                game.render(
                    dt: 1 / 60, input: GameInput(forward: true), secondaryInput: GameInput(reverse: true),
                    now: 1 / 60,
                    sendSecondary: { p2.append($0) }, send: { p1.append($0) }))
            XCTAssertTrue(p1.isEmpty)
            XCTAssertEqual(p2.count, 1)
            XCTAssertTrue(p2[0].reverse)
            XCTAssertEqual(shown.tanks.first { $0.id == 2 }?.x, 499)
            XCTAssertTrue(
                shown.spectating, "The viewer remains a spectator; only the owned P2 predictor is active")
        }
    }

    func testSecondaryUsesLocalInstantEffectsAndContactPose() {
        let presenter = CannonFlightPresenter()
        let beams = [
            ArenaEffect(id: 1, kind: "laser", owner: 2, tick: 100),
            ArenaEffect(id: 2, kind: "laser", owner: 3, tick: 100),
        ]
        presenter.accept(beams, throughTick: 100)
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 90, now: 1, authorityTick: 100, localID: 1, secondaryLocalID: 2)
        XCTAssertEqual(presenter.effects(beams).map(\.owner), [2])

        let before = ArenaTank(id: 2, x: 100, spawnSerial: 1)
        let hit = ArenaEffect(
            id: 3, kind: "hit", owner: 3, tick: 100,
            contact: ImpactContact(
                projectileId: 0, kind: "laser", tick: 100, target: 2, spawnSerial: 1,
                before: ImpactContactPose(before)))
        var after = before
        after.hp = 0
        presenter.accept([hit], throughTick: 100, tanks: [after])
        presenter.append(
            to: &bullets, tick: 95, now: 1.01, authorityTick: 100, localID: 1, secondaryLocalID: 2)
        var rendered = [after]
        var previous = before
        previous.x = 50
        presenter.applyContacts(to: &rendered, from: [2: previous], previousTick: 90)
        XCTAssertEqual(
            rendered[0].x, 100,
            "P2 contact keeps its exact local pose rather than interpolating as a remote tank")
    }

    func testBothLocalChannelsKeepSixtyHzSequencesAcrossDisplayRates() {
        for hz in [60, 90, 120] {
            let game = timeline()
            game.accept(frame(), at: 0)
            var p1: [UInt64] = []
            var p2: [UInt64] = []
            for step in 1...hz {
                _ = game.render(
                    dt: 1 / Double(hz), input: GameInput(forward: true),
                    secondaryInput: GameInput(reverse: true),
                    now: Double(step) / Double(hz), sendSecondary: { p2.append($0.seq) },
                    send: { p1.append($0.seq) })
            }
            XCTAssertEqual(p1, Array(1...60).map(UInt64.init))
            XCTAssertEqual(p2, p1)
        }
    }

}
