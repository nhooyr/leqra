import XCTest

/// Online smoke tests use `PORT=18081 go run ./src` on the simulator host.
/// Physical-device online tests can supply LEQRA_TEST_SERVER with a LAN URL.
/// Screenshots are XCTest attachments, never repository artifacts.
final class GameUITests: XCTestCase {
    private let publicSessionTestNamespace = "ui-" + UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Local development server permission") { alert in
            guard alert.label.localizedCaseInsensitiveContains("local network") || alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'local network'")).count > 0,
                  alert.buttons["Allow"].exists else { return false }
            alert.buttons["Allow"].tap(); return true
        }
    }

    @MainActor
    func testPublicInfinityHidesUnusedRoomRules() {
        let app = launch()
        selectPublic(true, in: app)
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Room settings'")).firstMatch
        reveal(settings, in: app); settings.tap()
        XCTAssertTrue(app.staticTexts["publicInfinityRulesNotice"].exists)
        XCTAssertFalse(app.buttons["mode_elimination"].exists)
        XCTAssertFalse(app.buttons["Rules"].exists)
        XCTAssertFalse(app.buttons["Presets"].exists)
        selectPublic(false, in: app)
        XCTAssertFalse(app.staticTexts["publicInfinityRulesNotice"].exists)
        XCTAssertTrue(app.buttons["mode_elimination"].exists)
        XCTAssertTrue(app.buttons["Rules"].exists)
        app.terminate()
    }

    @MainActor
    func testControlsSwitchesFitPortraitAndLandscape() {
        let app = launch(arguments: ["--probe-touch-only-controls"])
        let sidebar = app.buttons["Open sidebar"]
        let controls = app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebar.frame.midY, controls.frame.midY, accuracy: 1)
        XCTAssertLessThan(sidebar.frame.maxX, controls.frame.maxX)
        sidebar.tap()
        XCTAssertEqual(app.staticTexts["manualGamepadHint"].label, "Connect a game controller to play.")
        app.buttons["Close Sidebar"].tap()
        controls.tap()
        XCTAssertFalse(app.staticTexts["manualGamepadHint"].exists)
        let gameController = app.switches["settingGamepadSupport"]
        XCTAssertEqual(gameController.label, "Game controller support")
        XCTAssertEqual(gameController.value as? String, "1")
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            waitForOrientation(app, landscape: landscape)
            XCTAssertFalse(app.buttons["Binds"].exists)
            XCTAssertFalse(app.buttons["bind0_forward"].exists)
            XCTAssertFalse(app.buttons["resetBindings"].exists)
            XCTAssertFalse(app.switches["settingMouseAim"].exists)
            XCTAssertFalse(app.switches["settingMouseFire"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Keyboard defaults'")).firstMatch.exists)
            XCTAssertTrue(app.buttons["quickTour"].exists)
            XCTAssertTrue(app.buttons["openShowcase"].exists)
            XCTAssertEqual(app.buttons["settingsAccount"].label, "ACCOUNT KEY")
            XCTAssertFalse(app.buttons["settingsLocalAccount"].exists)
            for identifier in ["settingHighFrameRate", "settingShowFPS", "settingGamepadSupport", "settingSound"] {
                let toggle = app.switches[identifier]; reveal(toggle, in: app)
                let panel = app.scrollViews["modalScroll"].frame
                XCTAssertGreaterThanOrEqual(toggle.frame.minX, panel.minX)
                XCTAssertLessThanOrEqual(toggle.frame.maxX, panel.maxX - 8)
                XCTAssertGreaterThanOrEqual(toggle.frame.width, 50)
                let previous = toggle.value as? String
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                XCTAssertNotEqual(toggle.value as? String, previous)
            }
            capture(app, name: "Controls switches \(landscape ? "landscape" : "portrait")")
        }
        app.terminate()
    }

    @MainActor
    func testShowcaseBackgroundReturnRestoresControls() async throws {
        let app = launch()
        let name = app.textFields["callsignField"].value as? String
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.tap()
        let open = app.buttons["openShowcase"]
        for _ in 0..<12 where !app.scrollViews["modalScroll"].frame.contains(open.frame) { app.scrollViews["modalScroll"].swipeUp() }
        open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let stage = app.descendants(matching: .any)["showcaseStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        capture(app, name: "Showcase before app switch")
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 700_000_000)
        app.activate()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["Close Controls"].exists)
        app.buttons["Close Controls"].tap()
        XCTAssertEqual(app.textFields["callsignField"].value as? String, name)
        app.terminate()
    }

    @MainActor
    func testHardwareEscapeNotificationClosesBothOverlays() {
        let app = launch(arguments: ["--probe-hardware-controls", "--probe-hardware-escape"])
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.tap()
        let binds = app.buttons["Binds"]; reveal(binds, in: app); binds.tap()
        let bind = app.buttons["bind0_forward"]; reveal(bind, in: app)
        bind.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Press a key"].waitForExistence(timeout: 5))
        let captureGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Press a key"])
        XCTAssertEqual(XCTWaiter.wait(for: [captureGone], timeout: 5), .completed)
        let open = app.buttons["openShowcase"]; reveal(open, in: app)
        open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let stage = app.descendants(matching: .any)["showcaseStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        let showcaseGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [showcaseGone], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["Close Controls"].exists)
        app.terminate()
    }

    @MainActor
    func testHardwareEscapeExitsShowcase() throws {
        guard ProcessInfo.processInfo.environment["LEQRA_HARDWARE_ESCAPE_UI"] == "1" else {
            throw XCTSkip("Requires a hardware route that delivers Escape; this simulator intercepts named and literal Escape before UIKit.")
        }
        let app = launch()
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.tap()
        let open = app.buttons["openShowcase"]; reveal(open, in: app)
        open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let stage = app.descendants(matching: .any)["showcaseStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        hardwareKey(XCUIKeyboardKey.escape.rawValue, in: app)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        app.terminate()
    }

    @MainActor
    func testShowcaseRendersAndRestoresOnAppReturn() async throws {
        let app = launch(callsign: "SCENE " + UUID().uuidString.prefix(8), arguments: [])
        let originalName = app.textFields["callsignField"].value as? String
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.tap()
        let open = app.buttons["openShowcase"]
        for _ in 0..<12 where !app.scrollViews["modalScroll"].frame.contains(open.frame) { app.scrollViews["modalScroll"].swipeUp() }
        print("Showcase before tap: " + open.debugDescription)
        open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let stage = app.descendants(matching: .any)["showcaseStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Close Controls"].isHittable)
        let header = app.staticTexts["showcaseBrand"]
        let status = app.staticTexts["showcaseTitle"]
        let loadout = app.staticTexts["pilotIdentity"]
        XCTAssertTrue(header.exists); XCTAssertTrue(status.exists); XCTAssertTrue(loadout.exists)
        XCTAssertLessThanOrEqual(header.frame.maxY, stage.frame.minY)
        XCTAssertGreaterThanOrEqual(loadout.frame.minY, stage.frame.maxY)
        XCTAssertEqual(app.staticTexts["pilotIdentity"].label, "aqsnow (P1)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'LASER'")).firstMatch.exists)
        try await Task.sleep(nanoseconds: 300_000_000)
        let pixelsBefore = stage.screenshot().image.cgImage?.dataProvider?.data
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let stick = origin.withOffset(CGVector(dx: stage.frame.minX + 84, dy: stage.frame.maxY - 63))
        stick.press(forDuration: 0.05, thenDragTo: stick.withOffset(CGVector(dx: 25, dy: -25)), withVelocity: .slow, thenHoldForDuration: 0.2)
        origin.withOffset(CGVector(dx: stage.frame.maxX - 63.5, dy: stage.frame.maxY - 63)).press(forDuration: 0.2)
        XCTAssertEqual(pixelsBefore as Data?, stage.screenshot().image.cgImage?.dataProvider?.data as Data?, "The displayed gameplay controls must leave the frozen scene unchanged.")
        capture(app, name: "Showcase portrait with gameplay chrome")
        XCTAssertTrue(stage.exists, "Touch gestures must not dismiss Showcase.")
        XCUIDevice.shared.orientation = .landscapeLeft; waitForOrientation(app, landscape: true)
        XCTAssertTrue(header.exists); XCTAssertTrue(loadout.exists)
        capture(app, name: "Showcase landscape with gameplay chrome")
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 700_000_000)
        app.activate()
        XCTAssertTrue(app.buttons["Close Controls"].waitForExistence(timeout: 10))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        app.buttons["Close Controls"].tap()
        XCTAssertEqual(app.textFields["callsignField"].value as? String, originalName)
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate()
    }

    @MainActor
    func testLocalP2ManualSetupEveryModeAndSplitLayouts() async throws {
        let app = launch(callsign: "FIRST " + UUID().uuidString.prefix(8), arguments: ["--probe-local-p2-input", "-localCallsign", "MWMWMWMWMWMWMWMW"])
        selectPublic(false, in: app)
        openPlayers(in: app)
        let add = app.buttons["addLocalP2"]; reveal(add, in: app); add.tap()
        let local = app.textFields["localCallsignField"]
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        let name = local.value as? String ?? ""
        XCTAssertFalse(name.isEmpty)
        let removal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '"))
        while removal.count > 0 {
            let button = removal.firstMatch; reveal(button, in: app); button.tap()
        }
        for mode in ["infinity", "elimination", "ctf", "koth", "survival"] {
            selectMode(mode, in: app); play(in: app)
            let p2 = app.staticTexts["pilotIdentityP2"]
            XCTAssertTrue(p2.waitForExistence(timeout: 10))
            XCTAssertEqual(p2.label, name + " (P2)")
            XCTAssertTrue(app.descendants(matching: .any)["pilotAmmoP2"].firstMatch.exists)
            if mode == "infinity" {
                let stage = arena(in: app)
                let before = p2InputState(stage)
                for _ in 0..<8 { hardwareKey("a", in: app) }
                try await Task.sleep(nanoseconds: 200_000_000)
                let after = p2InputState(stage)
                XCTAssertNotEqual(before["p2a"], after["p2a"], "Hardware keyboard must rotate P2.")
                XCTAssertEqual(before["p1a"]!, after["p1a"]!, accuracy: 0.001, "Hardware keyboard must not rotate touch P1.")
                exerciseControls(in: app)
                let touched = p2InputState(stage)
                XCTAssertEqual(after["p2a"]!, touched["p2a"]!, accuracy: 0.001, "Touch must not steer P2.")
            } else { exerciseControls(in: app, fixedPortrait: true) }
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                waitForOrientation(app, landscape: landscape)
                XCTAssertTrue(p2.exists)
                XCTAssertTrue(app.staticTexts["pilotIdentity"].exists)
                XCTAssertTrue(app.frame.contains(p2.frame))
                if mode == "infinity" {
                    let first = app.descendants(matching: .any)["arenaStage"].firstMatch
                    let second = app.descendants(matching: .any)["secondaryArenaStage"].firstMatch
                    XCTAssertTrue(second.exists)
                    if landscape { XCTAssertLessThan(first.frame.midX, second.frame.midX) }
                    else { XCTAssertLessThan(first.frame.midY, second.frame.midY) }
                }
                capture(app, name: "P2 \(mode) \(landscape ? "landscape" : "portrait")")
            }
            leaveGame(in: app)
        }
        openPlayers(in: app)
        let remove = app.buttons["removeLocalP2"]; reveal(remove, in: app); remove.tap()
        XCTAssertTrue(app.buttons["addLocalP2"].exists)
        XCTAssertFalse(app.textFields["localCallsignField"].exists)
        app.terminate()
    }

    @MainActor
    func testOnlineP2PublicAndPrivateInputsRemainIndependent() async throws {
        try requireOnlineTestServer()
        let app = launch(callsign: "DUO " + UUID().uuidString.prefix(8), arguments: ["--probe-local-p2-input"])
        openPlayers(in: app)
        let add = app.buttons["addLocalP2"]; reveal(add, in: app); add.tap()
        let name = app.textFields["localCallsignField"].value as? String ?? ""
        XCTAssertFalse(name.isEmpty)
        selectPublic(true, in: app); play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentityP2"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["pilotIdentityP2"].label, name + " (P2)")
        let before = p2InputState(arena(in: app))
        for _ in 0..<8 { hardwareKey("a", in: app) }
        try await Task.sleep(nanoseconds: 600_000_000)
        let after = p2InputState(arena(in: app))
        XCTAssertNotEqual(before["p2a"], after["p2a"])
        if before["p1life"] == after["p1life"] { XCTAssertEqual(before["p1a"]!, after["p1a"]!, accuracy: 0.01) }
        capture(app, name: "Public Infinity P2 hardware input")
        leaveGame(in: app)
        selectPublic(false, in: app); selectMode("elimination", in: app)
        openPlayers(in: app)
        let removal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '"))
        while removal.count > 0 { let button = removal.firstMatch; reveal(button, in: app); button.tap() }
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'SHARE ROOM ONLINE'")).firstMatch
        reveal(share, in: app); share.tap()
        XCTAssertTrue(app.staticTexts["roomCodeValue"].waitForExistence(timeout: 15))
        play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentityP2"].waitForExistence(timeout: 10))
        capture(app, name: "Private match P2 independent account")
        try await Task.sleep(nanoseconds: 3_200_000_000)
        let fixedBefore = p2InputState(arena(in: app))
        for _ in 0..<5 { hardwareKey("a", in: app) }
        hardwareKey("q", in: app)
        try await Task.sleep(nanoseconds: 300_000_000)
        let fixedAfter = p2InputState(arena(in: app))
        XCTAssertNotEqual(fixedBefore["p2a"], fixedAfter["p2a"])
        if fixedBefore["p1life"] == fixedAfter["p1life"] { XCTAssertEqual(fixedBefore["p1a"]!, fixedAfter["p1a"]!, accuracy: 0.01) }
        exerciseControls(in: app, fixedPortrait: true)
        pause(in: app)
        let room = app.buttons["Return to room"]; reveal(room, in: app); room.tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        openPlayers(in: app)
        let addBot = app.buttons["Add bot"]; reveal(addBot, in: app); addBot.tap()
        let menu = app.buttons["pilotMenu_0"]; reveal(menu, in: app); menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Spectate"].tap()
        try await Task.sleep(nanoseconds: 500_000_000)
        let startWatched = app.buttons["playRoom"]; reveal(startWatched, in: app); startWatched.tap()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pilotIdentityP2"].waitForExistence(timeout: 10))
        try await Task.sleep(nanoseconds: 3_200_000_000)
        let watcherStage = arena(in: app)
        let roundLabel = app.staticTexts.matching(NSPredicate(format: "label MATCHES 'ROUND [0-9]+'")).firstMatch
        XCTAssertTrue(roundLabel.waitForExistence(timeout: 5))
        var watcherBefore = p2InputState(watcherStage), watcherAfter = watcherBefore
        var turned = false
        // A bot can kill P2 between a batch of keys and the final snapshot,
        // resetting the new round's angle to the same value as the old one.
        // Require an observed turn from one key while P2 stays alive in one round.
        for attempt in 0..<12 {
            let roundBefore = roundLabel.label
            watcherBefore = p2InputState(watcherStage)
            hardwareKey("a", in: app)
            watcherAfter = p2InputState(watcherStage)
            let roundAfter = roundLabel.label
            print("Private P1 spectator input attempt \(attempt): \(roundBefore) -> \(roundAfter), before=\(watcherBefore), after=\(watcherAfter)")
            if let beforeAngle = watcherBefore["p2a"], let afterAngle = watcherAfter["p2a"],
               watcherBefore["p2hp", default: 0] > 0, watcherAfter["p2hp", default: 0] > 0,
               watcherBefore["p2life"] == watcherAfter["p2life"], roundBefore == roundAfter,
               beforeAngle != afterAngle {
                turned = true
                break
            }
        }
        capture(app, name: "Private P1 spectator and active P2")
        XCTAssertTrue(turned, "P2 must turn while alive when P1 watches a fixed match. before=\(watcherBefore), after=\(watcherAfter)")
        XCTAssertEqual(app.alerts.count, 0)
        leaveGame(in: app); app.terminate()
    }

    @MainActor
    func testHardwareBindingsMouseTogglesAndQuickTour() {
        let app = launch(arguments: ["--probe-hardware-controls"])
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.tap()
        let binds = app.buttons["Binds"]; reveal(binds, in: app)
        XCTAssertEqual(binds.value as? String, "Collapsed")
        let binding = app.buttons["bind0_forward"]
        XCTAssertFalse(binding.exists)
        XCTAssertFalse(app.switches["settingMouseAim"].exists)
        binds.tap()
        XCTAssertEqual(binds.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Keyboard defaults'")).firstMatch.exists)
        reveal(binding, in: app); binding.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Press a key"].waitForExistence(timeout: 5))
        hardwareKey("a", in: app)
        XCTAssertTrue(app.staticTexts["bindingError"].waitForExistence(timeout: 5))
        hardwareKey("i", in: app)
        XCTAssertTrue(binding.waitForExistence(timeout: 5))
        XCTAssertEqual(binding.label, "I")
        let other = app.buttons["bind1_forward"]
        reveal(other, in: app); other.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        hardwareKey("i", in: app)
        XCTAssertTrue(app.staticTexts["bindingError"].waitForExistence(timeout: 5))
        if ProcessInfo.processInfo.environment["LEQRA_HARDWARE_ESCAPE_UI"] == "1" {
            hardwareKey(XCUIKeyboardKey.escape.rawValue, in: app)
        } else {
            app.buttons["CANCEL"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let captureGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Press a key"])
        XCTAssertEqual(XCTWaiter.wait(for: [captureGone], timeout: 5), .completed)
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        for name in ["settingMouseAim", "settingMouseFire"] {
            let toggle = app.switches[name]; reveal(toggle, in: app)
            let before = toggle.value as? String; toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertNotEqual(toggle.value as? String, before)
            XCTAssertLessThanOrEqual(toggle.frame.maxX, app.scrollViews["modalScroll"].frame.maxX)
        }
        let reset = app.buttons["resetBindings"]; reveal(reset, in: app); reset.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(binding.label, "W")
        reveal(binds, in: app); binds.tap()
        XCTAssertEqual(binds.value as? String, "Collapsed")
        XCTAssertFalse(binding.exists)
        XCTAssertFalse(app.switches["settingMouseAim"].exists)
        let tour = app.buttons["quickTour"]; reveal(tour, in: app)
        let actions = app.scrollViews["modalScroll"].buttons.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(Array(actions.drop(while: { $0 != "Binds" }).prefix(4)),
                       ["Binds", "quickTour", "openShowcase", "settingsAccount"])
        tour.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Quick tour"].waitForExistence(timeout: 5))
        let excludedTourTerms = ["keyboard", "mouse", "gamepad", "game controller", "P1", "P2"]
        let next = app.buttons["tourNext"]
        let stage = app.descendants(matching: .any)["tourPracticeArena"].firstMatch
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let score = app.staticTexts["tourScore"]
        var firstStageFrame: CGRect?
        for (page, heading) in ["Drive and aim", "Fire", "Score a point"].enumerated() {
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5))
            let instructions = app.staticTexts["tourInstructions"]
            XCTAssertTrue(instructions.exists)
            XCTAssertFalse(excludedTourTerms.contains { instructions.label.localizedCaseInsensitiveContains($0) })
            XCTAssertTrue(stage.waitForExistence(timeout: 5))
            XCTAssertFalse(next.isEnabled)
            if page == 2 {
                XCTAssertEqual(instructions.label, "Destroy the stationary tank to score a point.")
                XCTAssertEqual(score.label, "score: 0")
            } else { XCTAssertFalse(score.exists) }
            let frame = stage.frame
            if let firstStageFrame {
                XCTAssertEqual(frame.minX, firstStageFrame.minX, accuracy: 1)
                XCTAssertEqual(frame.minY, firstStageFrame.minY, accuracy: 1)
                XCTAssertEqual(frame.width, firstStageFrame.width, accuracy: 1)
                XCTAssertEqual(frame.height, firstStageFrame.height, accuracy: 1)
            } else { firstStageFrame = frame }
            let fire = origin.withOffset(CGVector(dx: frame.maxX - 85.5, dy: frame.maxY - 63))
            fire.press(forDuration: 0.06)
            if page == 0 {
                XCTAssertFalse(next.isEnabled, "Fire cannot complete the movement exercise.")
                let stick = origin.withOffset(CGVector(dx: frame.minX + 93, dy: frame.maxY - 63))
                stick.press(forDuration: 0.05, thenDragTo: stick.withOffset(CGVector(dx: 31, dy: 0)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            if page == 2 { XCTAssertEqual(score.label, "score: 1") }
            next.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.buttons["Close Controls"].waitForExistence(timeout: 5))
        let all = app.buttons["resetAllSettings"]; reveal(all, in: app); all.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Reset all settings"].waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.03)).tap() }
        XCTAssertTrue(app.buttons["Close Controls"].exists)
        capture(app, name: "Hardware bindings and mouse settings")
        app.terminate()
    }

    @MainActor
    func testFixedP2KeepsHardwareWhenP1Spectates() async throws {
        try requireOnlineTestServer()
        let app = launch(arguments: ["--probe-local-p2-input"])
        selectPublic(false, in: app); selectMode("elimination", in: app)
        openPlayers(in: app)
        let removal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '"))
        while removal.count > 0 { let button = removal.firstMatch; reveal(button, in: app); button.tap() }
        let add = app.buttons["addLocalP2"]; reveal(add, in: app); add.tap()
        let bot = app.buttons["Add bot"]; reveal(bot, in: app); bot.tap()
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'SHARE ROOM ONLINE'")).firstMatch
        reveal(share, in: app); share.tap()
        XCTAssertTrue(app.staticTexts["roomCodeValue"].waitForExistence(timeout: 15))
        openPlayers(in: app)
        let menu = app.buttons["pilotMenu_0"]; reveal(menu, in: app)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Spectate"].waitForExistence(timeout: 5)); app.buttons["Spectate"].tap()
        let play = app.buttons["playRoom"]; reveal(play, in: app); play.tap()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pilotIdentityP2"].waitForExistence(timeout: 10))
        try await Task.sleep(nanoseconds: 3_200_000_000)
        let before = p2InputState(arena(in: app))
        for _ in 0..<3 { hardwareKey("a", in: app) }
        let after = p2InputState(arena(in: app))
        XCTAssertNotEqual(before["p2a"], after["p2a"], "before=\(before), after=\(after)")
        capture(app, name: "P1 watching, P2 hardware control")
        app.terminate()
    }

    @MainActor
    func testGameplayEnduranceAcrossEveryMode() async throws {
        guard let minutes = ProcessInfo.processInfo.environment["LEQRA_ENDURANCE_MINUTES"].flatMap(Double.init), minutes > 0 else {
            throw XCTSkip("Opt in to a sustained native gameplay audit.")
        }
        let app = launch(callsign: "SOAK " + UUID().uuidString.prefix(8))
        selectPublic(false, in: app)
        let modes = ["elimination", "ctf", "koth", "survival", "infinity"]
        let deadline = Date().addingTimeInterval(min(100, minutes) * 60)
        var round = 0
        while Date() < deadline {
            XCUIDevice.shared.orientation = .portrait
            selectMode(modes[round % modes.count], in: app)
            play(in: app)
            for pass in 0..<12 {
                if Date() >= deadline { break }
                exerciseControls(in: app, fixedPortrait: modes[round % modes.count] != "infinity")
                if pass % 4 == 0 {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    waitForOrientation(app, landscape: true)
                    exerciseControls(in: app)
                    XCUIDevice.shared.orientation = .portrait
                    waitForOrientation(app, landscape: false)
                }
                if pass % 3 == 0 {
                    pause(in: app)
                    if pass % 2 == 0 {
                        XCUIDevice.shared.press(.home)
                        try await Task.sleep(nanoseconds: 500_000_000)
                        app.activate()
                        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10))
                    }
                    app.buttons["Resume"].tap()
                    XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 10))
                }
                XCTAssertEqual(app.alerts.count, 0)
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            capture(app, name: "Endurance round \(round) " + modes[round % modes.count])
            leaveGame(in: app)
            round += 1
            print("Native endurance completed round \(round), remaining seconds \(Int(deadline.timeIntervalSinceNow))")
        }
        app.terminate()
    }

    @MainActor
    func testPublicInfinityRecoveryEndurance() async throws {
        guard let minutes = ProcessInfo.processInfo.environment["LEQRA_PUBLIC_ENDURANCE_MINUTES"].flatMap(Double.init), minutes > 0 else {
            throw XCTSkip("Opt in to repeated public Infinity foreground/background recovery.")
        }
        try requireOnlineTestServer()
        let name = "NET " + UUID().uuidString.prefix(8)
        let app = launch(callsign: name)
        selectPublic(true, in: app); play(in: app)
        let deadline = Date().addingTimeInterval(min(60, minutes) * 60)
        var round = 0
        while Date() < deadline {
            for _ in 0..<4 { exerciseControls(in: app) }
            let manuallyPaused = round % 2 == 0
            if manuallyPaused { pause(in: app) }
            XCUIDevice.shared.press(.home)
            try await Task.sleep(nanoseconds: 1_200_000_000)
            app.activate()
            if manuallyPaused {
                XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 15))
                app.buttons["Resume"].tap()
            }
            XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(name))
            XCTAssertFalse(app.buttons["Chat"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            XCUIDevice.shared.orientation = round % 2 == 0 ? .landscapeLeft : .portrait
            waitForOrientation(app, landscape: round % 2 == 0)
            capture(app, name: "Public recovery endurance \(round)")
            round += 1
        }
        leaveGame(in: app); app.terminate()
        print("Native public recovery completed \(round) background cycles")
    }

    @MainActor
    func testPublicBackgroundRecoveryPreservesActiveAndManualPauseIntent() async throws {
        try requireOnlineTestServer()
        let name = "WARM " + UUID().uuidString.prefix(8)
        let app = launch(callsign: name)
        selectPublic(true, in: app); play(in: app)
        for wasPaused in [false, true] {
            if wasPaused { pause(in: app) }
            XCUIDevice.shared.press(.home)
            try await Task.sleep(nanoseconds: 600_000_000)
            app.activate()
            if wasPaused {
                XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 20), "An authenticated paused session must remain paused after recovery")
                app.buttons["Resume"].tap()
            } else {
                XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.buttons["Resume"].exists, "An active session resumes automatically")
            }
            XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(name))
            XCTAssertEqual(app.alerts.count, 0)
        }
        leaveGame(in: app)
        app.terminate()
    }

    @MainActor
    func testSelectingLocalModeKeepsAnIntentionallyEmptyRoster() {
        let app = launch()
        selectPublic(false, in: app)
        openPlayers(in: app)
        let removal = NSPredicate(format: "label BEGINSWITH 'Remove '")
        for _ in 0..<3 {
            let button = app.buttons.matching(removal).firstMatch
            reveal(button, in: app); button.tap()
        }
        XCTAssertEqual(app.buttons.matching(removal).count, 0)
        selectMode("survival", in: app)
        XCTAssertEqual(app.buttons.matching(removal).count, 0, "An explicit local mode change must preserve an empty custom roster")
        app.terminate()
    }

    @MainActor
    func testFinalPowerUpTapNeverAlsoFiresStandardAmmo() async throws {
        for fixed in [false, true] { for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
            let app = XCUIApplication()
            app.launchArguments = ["--probe-direct-aim", "--probe-final-charge", "--probe-weapon", weapon,
                                   "--public-session-test-namespace", "last-ammo-" + UUID().uuidString]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let stage = arena(in: app)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.p2InputState(stage)["ammoEpoch"] == 0
            }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            let frame = stage.frame
            let fire = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: frame.maxX - (fixed ? 86 : 64), dy: frame.maxY - (fixed ? 60 : 68)))
            fire.press(forDuration: 0.1)
            try await Task.sleep(nanoseconds: 450_000_000)
            let tapped = p2InputState(stage)
            XCTAssertEqual(tapped["ammoEpoch"], 1, "The final \(weapon) charge must be consumed")
            XCTAssertEqual(tapped["standardBullets"], 0, "A short final \(weapon) tap also fired standard ammo")
            if weapon == "grenade" { fire.press(forDuration: 0.05) }
            fire.press(forDuration: 1.1)
            XCTAssertGreaterThan(p2InputState(stage)["standardBullets"] ?? 0, 0,
                "Genuinely held fire must continue with standard ammo after reload")
            capture(app, name: "Final \(weapon) charge and held continuation \(fixed ? "fixed" : "Infinity")")
            app.terminate()
        } }
    }

    @MainActor
    func testCannonTouchShotPiercesTheWholeTargetLine() {
        for fixed in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--probe-direct-aim", "--probe-weapon", "cannon", "--probe-cannon-line",
                                   "--public-session-test-namespace", "cannon-" + UUID().uuidString]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let stage = arena(in: app)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (stage.value as? String)?.contains("targets=3") == true }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            let frame = stage.frame, origin = app.coordinate(withNormalizedOffset: .zero)
            let fire = origin.withOffset(CGVector(dx: frame.maxX - (fixed ? 86 : 64), dy: frame.maxY - (fixed ? 60 : 68)))
            fire.press(forDuration: 0.05)
            let pierced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let data = (stage.value as? String) ?? ""
                return data.contains("score=3") && data.contains("charges=2")
            }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [pierced], timeout: 1.5), .completed, stage.value as? String ?? "No arena telemetry")
            capture(app, name: "One Cannon shot pierces three tanks " + (fixed ? "fixed" : "Infinity"))
            app.terminate()
        }
    }

    @MainActor
    func testOnlineRoomsDoNotExposeChat() throws {
        try requireOnlineTestServer()
        let app = launch(callsign: "ROOM " + UUID().uuidString.prefix(8))
        selectPublic(false, in: app)
        let share = app.buttons["SHARE ROOM ONLINE ↗"]
        reveal(share, in: app); share.tap()
        XCTAssertTrue(app.staticTexts["roomCodeValue"].waitForExistence(timeout: 15))
        func noChat() {
            XCTAssertFalse(app.buttons["Chat"].exists)
            XCTAssertFalse(app.textFields["Message"].exists)
        }
        noChat()
        for mode in ["elimination", "ctf", "koth", "survival", "infinity"] {
            selectMode(mode, in: app); play(in: app); noChat()
            capture(app, name: "Online " + mode + " without native chat")
            pause(in: app)
            app.buttons["Return to room"].tap()
            XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
            noChat()
        }
        app.terminate()
    }

    @MainActor
    func testLongPresetNameOverwritesItsNormalizedRow() {
        let app = launch()
        selectPublic(false, in: app)
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Room settings'")).firstMatch
        reveal(settings, in: app); settings.tap()
        let presets = app.buttons["Presets"]
        reveal(presets, in: app); presets.tap()
        let name = "AUDIT " + UUID().uuidString + " EXTRA LONG"
        let field = app.textFields["Preset name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            field.tap(); field.typeText(name + "\n")
            let save = app.buttons["SAVE ROOM"]
            if !save.isHittable { app.scrollViews["modalScroll"].swipeUp() }
            save.tap()
        }
        let normalized = String(name.prefix(40))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", normalized)).count, 1,
                       "Saving the same long name must replace its row instead of creating duplicate IDs")
        capture(app, name: "Long room preset name saves once")
        app.terminate()
    }

    @MainActor
    func testSavedCallsignScoresSwitchBackAndManualReleaseStayIndependent() throws {
        try requireOnlineTestServer()
        let first = "ONE " + UUID().uuidString.prefix(6), second = "TWO " + UUID().uuidString.prefix(6)
        let app = launch(callsign: first)
        selectPublic(true, in: app); play(in: app); leaveGame(in: app)
        func editName(_ name: String) {
            let field = app.textFields["callsignField"]
            reveal(field, in: app); field.tap()
            let old = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 1) + name + "\n")
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        }
        editName(second)
        let open = app.buttons["openAccount"]
        reveal(open, in: app); open.tap()
        let firstUse = app.buttons["USE " + first], secondUse = app.buttons["USE " + second]
        XCTAssertTrue(firstUse.waitForExistence(timeout: 10))
        XCTAssertTrue(secondUse.waitForExistence(timeout: 10))
        XCTAssertFalse(secondUse.isEnabled)
        let newScore = app.staticTexts["savedCallsignScore-" + second]
        let zero = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Score: 0'"), object: newScore)
        XCTAssertEqual(XCTWaiter.wait(for: [zero], timeout: 10), .completed)
        firstUse.tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        if !app.scrollViews["modalScroll"].exists { reveal(open, in: app); open.tap() }
        XCTAssertTrue(firstUse.waitForExistence(timeout: 5))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: firstUse)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        capture(app, name: "Saved callsigns retain independent scores and active button is disabled")
        app.buttons["Close Account key"].tap()
        selectPublic(false, in: app); selectMode("infinity", in: app); play(in: app); pause(in: app)
        app.buttons["Controls"].tap()
        let account = app.buttons["settingsAccount"]
        for _ in 0..<5 where !account.isHittable { app.scrollViews["modalScroll"].swipeUp() }
        account.tap()
        XCTAssertTrue(app.buttons["USE " + second].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["USE " + second].isEnabled, "Saved accounts cannot bypass the active-game import restriction")
        app.buttons["Close Account key"].tap()
        app.buttons["Close Controls"].tap()
        app.buttons["Resume"].tap()
        leaveGame(in: app)
        reveal(open, in: app); open.tap()
        let release = app.buttons["releaseAccount"]
        for _ in 0..<12 where !release.isHittable { app.scrollViews["modalScroll"].swipeUp() }
        XCTAssertTrue(release.isEnabled)
        XCTAssertTrue(app.scrollViews["modalScroll"].frame.contains(release.frame), "Release must remain completely visible inside its scroller")
        release.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Release callsign and delete score"].tap()
        let released = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Callsign released'"), object: app.staticTexts["accountStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["USE " + first].exists)
        XCTAssertTrue(app.buttons["USE " + second].exists)
        capture(app, name: "Manual release preserves the other saved callsign")
        app.buttons["Close Account key"].tap()
        app.terminate()
    }

    @MainActor
    func testHeldDetonationCannotThrowAgainUntilRelease() throws {
        for fixed in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--probe-direct-aim", "--probe-weapon", "grenade",
                                   "--public-session-test-namespace", "detonate-" + UUID().uuidString]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let stage = arena(in: app)
            func value(_ key: String) -> Int? {
                ((stage.value as? String) ?? "").split(separator: ",").first { $0.hasPrefix(key + "=") }
                    .flatMap { Int($0.split(separator: "=").last ?? "") }
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in value("charges") == 3 }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            let frame = stage.frame, origin = app.coordinate(withNormalizedOffset: .zero)
            let fire = origin.withOffset(CGVector(dx: frame.maxX - (fixed ? 86 : 64), dy: frame.maxY - (fixed ? 60 : 68)))
            fire.press(forDuration: 0.05)
            let thrown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in value("grenades") == 1 && value("charges") == 2 }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [thrown], timeout: 5), .completed)
            fire.press(forDuration: 1.1)
            XCTAssertEqual(value("grenades"), 0, "Detonating then holding must not throw another grenade")
            XCTAssertEqual(value("charges"), 2, "Detonation cannot consume the next grenade charge")
            fire.press(forDuration: 0.05)
            let next = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in value("grenades") == 1 && value("charges") == 1 }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
            capture(app, name: "Grenade requires a fresh press after detonation " + (fixed ? "fixed" : "Infinity"))
            app.terminate()
        }
    }

    @MainActor
    func testUnlabelledControlsFitInPortraitAndLandscape() {
        for fixed in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--probe-direct-aim", "--public-session-test-namespace", "controls-" + UUID().uuidString]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15))
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                waitForOrientation(app, landscape: landscape)
                let stage = arena(in: app)
                let values = Dictionary(uniqueKeysWithValues: ((stage.value as? String) ?? "").split(separator: ",").compactMap { item -> (String, Double)? in
                    let pair = item.split(separator: "=")
                    guard pair.count == 2, let number = Double(pair[1]) else { return nil }
                    return (String(pair[0]), number)
                })
                XCTAssertEqual(values["controlLabels"], 0, "Neither touch control displays a caption")
                XCTAssertGreaterThanOrEqual(values["stickBottom"] ?? -1, 8,
                    "The lowest fully deflected thumb remains inside the stage")
                XCTAssertGreaterThanOrEqual(values["fireBottom"] ?? -1, 8,
                    "The complete readiness ring remains inside the stage")
                XCTAssertLessThanOrEqual(values["controlCenterY"] ?? 999, 65,
                    "The controls reclaim the former caption space")
                capture(app, name: "Unlabelled controls " + (fixed ? "fixed " : "Infinity ") + (landscape ? "landscape" : "portrait"))
                exerciseControls(in: app, fixedPortrait: fixed && !landscape)
            }
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
    }

    @MainActor
    func testDirectAimTouchSnapsWithoutMovingInBothLayouts() throws {
        for fixed in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--probe-direct-aim", "--public-session-test-namespace", "aim-" + UUID().uuidString]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let stage = arena(in: app)
            func telemetry() -> [String: Double] {
                Dictionary(uniqueKeysWithValues: ((stage.value as? String) ?? "").split(separator: ",").compactMap { item in
                    let parts = item.split(separator: "=")
                    guard parts.count == 2, let number = Double(parts[1]) else { return nil }
                    return (String(parts[0]), number)
                })
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in telemetry()["screenX"] != nil }, object: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            for direction in [0.0, .pi / 2, .pi, -.pi / 2, -.pi / 4] {
                let before = telemetry(), frame = stage.frame
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let target = origin.withOffset(CGVector(dx: frame.minX + (before["screenX"] ?? 0) + cos(direction) * 40,
                                                        dy: frame.minY + (before["screenY"] ?? 0) + sin(direction) * 40))
                target.press(forDuration: 0.05)
                let aimed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    guard let angle = telemetry()["angle"] else { return false }
                    return abs(sin(angle - direction)) < 0.025 && cos(angle - direction) > 0.99
                }, object: stage)
                XCTAssertEqual(XCTWaiter.wait(for: [aimed], timeout: 5), .completed)
                let after = telemetry()
                XCTAssertEqual(try XCTUnwrap(after["x"]), try XCTUnwrap(before["x"]), accuracy: 0.0001)
                XCTAssertEqual(try XCTUnwrap(after["y"]), try XCTUnwrap(before["y"]), accuracy: 0.0001)
            }
            capture(app, name: "Direct aim touches " + (fixed ? "fixed" : "Infinity"))
            app.terminate()
        }
    }

    @MainActor
    func testPendingCallsignRegistrationCannotInterruptAnOfflineBattle() throws {
        guard let server = ProcessInfo.processInfo.environment["LEQRA_DELAYED_ACCOUNT_SERVER"] else {
            throw XCTSkip("Requires a delayed disposable account endpoint.")
        }
        for prefix in ["SLOW", "DOWN"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            let changed = prefix + " " + UUID().uuidString.prefix(6)
            app.launchArguments = ["-serverURL", server, "-callsign", "BEFORE",
                "--public-session-test-namespace", "delayed-name-" + UUID().uuidString, "--skip-public-session-restore"]
            app.launch()
            XCTAssertTrue(app.switches["publicInfinityToggle"].waitForExistence(timeout: 10))
            selectPublic(false, in: app); selectMode("infinity", in: app)
            let field = app.textFields["callsignField"]
            reveal(field, in: app); field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17) + changed + "\n")
            play(in: app)
            let survived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["pauseGame"].exists && app.staticTexts["pilotIdentity"].label.contains(changed) && app.alerts.count == 0
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [survived], timeout: 8), .completed)
            let delayed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: app)
            _ = XCTWaiter.wait(for: [delayed], timeout: 5.5)
            XCTAssertTrue(app.buttons["pauseGame"].exists, "A late account response cannot exit an already started local battle")
            XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(changed))
            XCTAssertEqual(app.alerts.count, 0)
            leaveGame(in: app); app.terminate()
        }
    }

    @MainActor
    func testPendingCallsignReleaseBlocksPlayAndFailureUnblocksIt() async throws {
        guard ProcessInfo.processInfo.environment["LEQRA_DELAYED_RELEASE_UI"] == "1" else {
            throw XCTSkip("Opt in with the disposable delayed_release_server.py fixture.")
        }
        try requireOnlineTestServer()
        for fails in [false, true] {
            let server = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"] ?? "http://127.0.0.1:18224"
            _ = try await URLSession.shared.data(from: URL(string: server + "/reset-release")!)
            let name = (fails ? "FAIL " : "RELEASE ") + UUID().uuidString.prefix(6)
            let app = XCUIApplication()
            app.launchArguments = ["-serverURL", server, "-callsign", "START",
                "--public-session-test-namespace", "release-" + UUID().uuidString, "--skip-public-session-restore"]
            XCUIDevice.shared.orientation = .portrait; app.launch()
            XCTAssertTrue(app.switches["publicInfinityToggle"].waitForExistence(timeout: 10))
            selectPublic(false, in: app)
            let field = app.textFields["callsignField"]
            reveal(field, in: app); field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + name + "\n")
            let account = app.buttons["openAccount"]
            reveal(account, in: app); account.tap()
            let release = app.buttons["releaseAccount"]
            let registered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: release)
            XCTAssertEqual(XCTWaiter.wait(for: [registered], timeout: 10), .completed)
            for _ in 0..<12 where !release.isHittable { app.scrollViews["modalScroll"].swipeUp() }
            release.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["Release callsign and delete score"].tap()
            app.buttons["Close Account key"].tap()
            let playButton = app.buttons["playRoom"]
            reveal(playButton, in: app)
            XCTAssertFalse(playButton.isEnabled, "Closing the account menu cannot bypass a pending release")
            XCTAssertFalse(field.isEnabled, "The pending release cannot be bypassed through the callsign editor")
            _ = try await URLSession.shared.data(from: URL(string: server + "/finish-release")!)
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: playButton)
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
            if fails { XCTAssertEqual(field.value as? String, name, "A failed release retains the selected account") }
            else { XCTAssertNotEqual(field.value as? String, name, "A successful release selects a fresh local account") }
            play(in: app); exerciseControls(in: app)
            XCTAssertTrue(app.buttons["pauseGame"].exists)
            capture(app, name: "Release " + (fails ? "failure" : "success") + " permits play after completion")
            leaveGame(in: app); app.terminate()
        }
    }

    @MainActor
    func testOfflineReadyRoomCallsignChangeSurvivesAnUnavailableServer() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let original = "OFF " + UUID().uuidString.prefix(6)
        let changed = "NEW " + UUID().uuidString.prefix(6)
        app.launchArguments = ["-serverURL", "http://127.0.0.1:1", "-callsign", original,
            "--public-session-test-namespace", "offline-name-" + UUID().uuidString, "--skip-public-session-restore"]
        app.launch()
        XCTAssertTrue(app.switches["publicInfinityToggle"].waitForExistence(timeout: 10))
        selectPublic(false, in: app)
        let field = app.textFields["callsignField"]
        reveal(field, in: app); field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 1) + changed + "\n")
        let feedback = app.staticTexts["callsignAvailability"]
        let unavailable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'could not be checked'"), object: feedback)
        XCTAssertEqual(XCTWaiter.wait(for: [unavailable], timeout: 10), .completed)
        XCTAssertEqual(app.alerts.count, 0, "Network failure cannot block a local callsign edit")
        XCTAssertEqual(field.value as? String, changed)
        selectMode("infinity", in: app)
        play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(changed))
        capture(app, name: "Offline callsign works while the server is unavailable")
        leaveGame(in: app)
        app.terminate()
        if let index = app.launchArguments.firstIndex(of: "-callsign") { app.launchArguments.removeSubrange(index...index + 1) }
        app.launch()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, changed, "The offline account draft must survive a cold launch")
        selectPublic(false, in: app); selectMode("infinity", in: app); play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(changed))
        leaveGame(in: app)
        app.terminate()
    }

    @MainActor
    func testUnchangedOfflineCallsignResumeKeepsItsBattleWithoutAnAccountKey() {
        for fixed in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--native-performance-probe", "--probe-weapon", "rapid", "--probe-seconds", "60",
                                   "--public-session-test-namespace", "resume-" + UUID().uuidString]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15))
            for _ in 0..<2 {
                pause(in: app)
                app.buttons["Resume"].tap()
                let stayedInBattle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.buttons["pauseGame"])
                XCTAssertEqual(XCTWaiter.wait(for: [stayedInBattle], timeout: 5), .completed)
                XCTAssertFalse(app.buttons["playRoom"].exists, "An unchanged callsign must not create an account and exit to the room")
            }
            capture(app, name: "Unchanged offline callsign resumes " + (fixed ? "fixed" : "Infinity"))
            app.terminate()
        }
    }

    @MainActor
    func testBackgroundAndRotationPreserveActiveAndPausedStackedPowerGames() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--native-performance-probe", "--probe-weapon", "starman", "--probe-bullets", "115",
                               "--probe-buffs", "shield,speed,ghost", "--probe-pan", "--probe-seconds", "60"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 600_000_000)
        app.activate()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Resume"].exists, "A previously active game resumes after activation")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.frame.contains(arena(in: app).frame))
        pause(in: app)
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 600_000_000)
        app.activate()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10), "A manually paused game must stay paused")
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        XCTAssertEqual(app.alerts.count, 0)
        capture(app, name: "Stacked Starman lifecycle and rotation")
        app.terminate()
    }

    @MainActor
    func testIncompatibleSurvivalSelectionKeepsEveryBotAndTheCurrentMode() {
        let app = launch()
        selectPublic(false, in: app); selectMode("elimination", in: app)
        openPlayers(in: app)
        for _ in 0..<3 { let add = app.buttons["Add bot"]; reveal(add, in: app); add.tap() }
        let before = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '")).allElementsBoundByIndex.map(\.label).sorted()
        XCTAssertEqual(before.count, 6)
        selectMode("survival", in: app)
        let notice = app.staticTexts["roomSetupError"]
        XCTAssertTrue(notice.label.contains("four squad tanks"))
        XCTAssertTrue(app.staticTexts["roomRuleSummary"].label.contains("WINS"), "A rejected mode cannot change its active rules")
        let after = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '")).allElementsBoundByIndex.map(\.label).sorted()
        XCTAssertEqual(after, before, "Changing modes cannot discard configured bots")
        capture(app, name: "Survival preserves six-bot roster and reports incompatibility")
        app.terminate()
    }

    @MainActor
    func testDisablingPublicInfinityThenSelectingModeStartsChosenLocalMode() {
        let app = launch()
        selectPublic(true, in: app)
        selectPublic(false, in: app)
        selectMode("ctf", in: app)
        XCTAssertEqual(app.switches["publicInfinityToggle"].value as? String, "0")
        play(in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'TEAM 1: FLAG'")).firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Explicit CTF selection starts native local CTF")
        app.terminate()
    }

    @MainActor
    func testInfinityPauseUsesDifficultyLabelsAndLocalIdentity() {
        let name = String(repeating: "界", count: 16)
        let app = launch(callsign: name)
        selectPublic(false, in: app); selectMode("infinity", in: app); play(in: app); pause(in: app)
        let scroll = app.scrollViews["pauseMenuScroll"]
        for _ in 0..<5 where !app.staticTexts["LEADERBOARD"].isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name + " (P1)")).firstMatch.exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'BOT'")).count, 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label IN {'DUMB', 'EASY', 'MEDIUM', 'HARD', 'GODLIKE'}")).firstMatch.exists)
        capture(app, name: "Pause leaderboard uses difficulty and full CJK local name")
        app.terminate()
    }

    @MainActor
    func testEmptyAmmoPressReachesTheActualBarrelWithoutCreatingAShot() {
        for fixed in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--native-performance-probe", "--probe-empty-fire-feedback", "--probe-audio-off"]
            if fixed { app.launchArguments.append("--probe-fixed") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let stage = arena(in: app)
            XCTAssertTrue(stage.waitForExistence(timeout: 15))
            let ready = NSPredicate { _, _ in (stage.value as? String)?.contains("ammoUsed=5") == true }
            expectation(for: ready, evaluatedWith: nil)
            waitForExpectations(timeout: 5)
            let frame = stage.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.maxX - 65, dy: frame.maxY - 65)).press(forDuration: 0.03)
            let kicked = NSPredicate { _, _ in
                guard let value = stage.value as? String, let raw = value.split(separator: ",").first?.split(separator: "=").last,
                      let position = Double(raw) else { return false }
                return position < -0.25
            }
            expectation(for: kicked, evaluatedWith: nil)
            waitForExpectations(timeout: 5)
            let value = stage.value as? String ?? ""
            XCTAssertTrue(value.contains("bullets=0")); XCTAssertTrue(value.contains("ammoUsed=5"))
            XCTAssertTrue(value.contains("infinity=\(!fixed)"))
            app.terminate()
        }
    }

    @MainActor
    func testRoamingSpawnRateIsConditionalAndPersistsInNativeRoomRules() async throws {
        let app = launch(callsign: "RATE " + UUID().uuidString.prefix(8))
        selectPublic(false, in: app); selectMode("infinity", in: app)
        let rules = app.buttons["Rules"]
        reveal(rules, in: app); rules.tap()
        let toggle = app.switches["randomRoamingBots"]
        let scroll = app.scrollViews["modalScroll"]
        func expose(_ element: XCUIElement) {
            for _ in 0..<12 {
                let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 4, dy: 8), frame = element.frame
                if frame.minY >= viewport.minY && frame.maxY <= viewport.maxY { return }
                let upward = frame.midY > viewport.midY
                let distance = min(160, max(65, abs(frame.midY - viewport.midY)))
                let origin = app.coordinate(withNormalizedOffset: .zero), x = viewport.minX + 10
                origin.withOffset(CGVector(dx: x, dy: viewport.midY + (upward ? distance / 2 : -distance / 2)))
                    .press(forDuration: 0.08, thenDragTo: origin.withOffset(CGVector(dx: x, dy: viewport.midY - (upward ? distance / 2 : -distance / 2))),
                           withVelocity: .slow, thenHoldForDuration: 0.15)
            }
            XCTFail("Could not reveal modal control \(element.identifier)")
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let nativeToggle = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        expose(nativeToggle)
        if toggle.value as? String == "1" { setSwitch(toggle, to: "0") }
        for tier in ["dumb", "easy", "normal", "hard", "godlike"] { XCTAssertFalse(app.buttons["roamingSpawnRate_\(tier)"].exists) }
        setSwitch(toggle, to: "1")
        let rate = app.buttons["roamingSpawnRate_normal"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        expose(rate)
        rate.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap(); app.buttons["4×"].tap()
        let apply = app.buttons["APPLY RULES"]
        expose(apply)
        apply.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        reveal(rules, in: app); rules.tap()
        XCTAssertTrue(app.buttons["roamingSpawnRate_normal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roamingSpawnRate_normal"].label.contains("4×"))
        for tier in ["dumb", "easy", "hard", "godlike"] { XCTAssertTrue(app.buttons["roamingSpawnRate_\(tier)"].label.contains("Off")) }
        expose(app.buttons["roamingSpawnRate_normal"])
        capture(app, name: "Native per-tier bot spawn rates portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        try await Task.sleep(nanoseconds: 700_000_000)
        for tier in ["dumb", "normal", "godlike"] {
            expose(app.buttons["roamingSpawnRate_\(tier)"])
            capture(app, name: "Native per-tier bot spawn rates landscape \(tier)")
        }
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate()
    }

    /// A disposable real Go host publishes an Infinity room with roaming bots.
    /// The viewer joins before start, follows rows beyond the first ten in both
    /// orientations, exits without ending the room, then watches a late join.
    @MainActor
    func testRoomInfinitySpectatorCanScrollFollowAndRejoinInBothOrientations() async throws {
        guard let code = ProcessInfo.processInfo.environment["LEQRA_SPECTATOR_UI_ROOM"] else {
            throw XCTSkip("Requires a disposable live Room Infinity host.")
        }
        try requireOnlineTestServer()
        let app = launch(callsign: "WATCH " + UUID().uuidString.prefix(7))
        func joinWatching() {
            let join = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Join another room'")).firstMatch
            reveal(join, in: app); join.tap()
            let field = app.textFields["joinRoomCode"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            field.typeText(code + "\n")
            let toggle = app.switches["joinSpectatingToggle"]
            if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            let watching = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [watching], timeout: 3), .completed)
            app.buttons["joinRoomButton"].tap()
            XCTAssertTrue(app.staticTexts["spectatorFollowing"].waitForExistence(timeout: 20), "Authorized viewers enter on room start or an active late join")
        }
        joinWatching()
        XCTAssertFalse(app.staticTexts["gameScore"].exists)
        XCTAssertFalse(app.staticTexts["pilotIdentity"].exists)
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            try await Task.sleep(nanoseconds: 700_000_000)
            let arenaBounds = app.otherElements["arenaStage"].frame
            if !app.buttons["closeStandings"].exists { app.buttons["toggleStandings"].tap() }
            let scroll = app.scrollViews["standingsScroll"]
            var selectedID: String?
            // Scores keep changing while the real host plays. Choose a
            // currently visible row beyond ten, then follow its stable ID.
            for _ in 0..<15 {
                let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'followTank_' AND label MATCHES %@", "^(1[1-9]|[2-9][0-9]+)\\..*" )).allElementsBoundByIndex
                if let row = rows.first(where: \.isHittable) { selectedID = row.identifier; break }
                scroll.swipeUp()
            }
            let target = try XCTUnwrap(selectedID, "The complete room leaderboard must scroll beyond row ten")
            let selectedRow = app.buttons[target]
            selectedRow.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Following'"), object: selectedRow)
            await fulfillment(of: [selected], timeout: 8)
            XCTAssertTrue(app.staticTexts["spectatorFollowing"].label.hasPrefix("FOLLOWING "))
            XCTAssertEqual(app.otherElements["arenaStage"].frame, arenaBounds, "Changing followed callsigns must not resize the arena")
            XCTAssertEqual(app.alerts.count, 0)
            capture(app, name: "Native Infinity spectator full leaderboard \(landscape ? "landscape" : "portrait")")
            app.buttons["closeStandings"].tap()
            capture(app, name: "Native Infinity spectator followed arena \(landscape ? "landscape" : "portrait")")
        }
        app.buttons["pauseGame"].tap()
        XCTAssertFalse(app.textFields["Callsign"].exists, "A spectator cannot rename an arena tank")
        app.buttons["Leave game"].tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(app.buttons["pauseGame"].exists, "Roster updates cannot undo an explicit exit")
        let leave = app.buttons["Leave room"]
        reveal(leave, in: app); leave.tap()
        joinWatching()
        XCTAssertTrue(app.staticTexts["spectatorFollowing"].exists)
        capture(app, name: "Native Infinity spectator automatic late join")
        app.terminate()
    }

    @MainActor
    func testRoomModeSwitchKeepsReadyCardAndPlayGeometryInBothOrientations() async throws {
        try requireOnlineTestServer()
        let app = launch(callsign: "MENU " + UUID().uuidString.prefix(8))
        selectPublic(false, in: app)
        selectMode("elimination", in: app)
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'SHARE ROOM ONLINE'")).firstMatch
        reveal(share, in: app); share.tap()
        XCTAssertTrue(app.staticTexts["roomCodeValue"].waitForExistence(timeout: 15))
        let card = app.otherElements["readyRoomCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        func top() async throws {
            let scroll = app.scrollViews["readyRoomScroll"]
            for _ in 0..<5 {
                if card.frame.minY >= scroll.frame.minY + 8 { break }
                scroll.swipeDown()
            }
            try await Task.sleep(nanoseconds: 700_000_000)
        }
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            try await Task.sleep(nanoseconds: 700_000_000)
            var baseline: (viewport: CGRect, card: CGRect, play: CGRect)?
            for mode in ["elimination", "infinity", "elimination"] {
                selectMode(mode, in: app)
                let summary = app.staticTexts["roomRuleSummary"]
                let rule = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", mode == "infinity" ? "ENDLESS" : "FIRST TO"), object: summary)
                await fulfillment(of: [rule], timeout: 10)
                try await top()
                let current = (viewport: app.scrollViews["readyRoomScroll"].frame, card: card.frame, play: app.buttons["playRoom"].frame)
                print("Native ready geometry \(landscape ? "landscape" : "portrait") \(mode): viewport=\(current.viewport), card=\(current.card), play=\(current.play)")
                if let baseline {
                    for pair in [(current.viewport, baseline.viewport), (current.card, baseline.card), (current.play, baseline.play)] {
                        XCTAssertEqual(pair.0.minX, pair.1.minX, accuracy: 0.5)
                        XCTAssertEqual(pair.0.minY, pair.1.minY, accuracy: 0.5)
                        XCTAssertEqual(pair.0.width, pair.1.width, accuracy: 0.5)
                        XCTAssertEqual(pair.0.height, pair.1.height, accuracy: 0.5)
                    }
                } else { baseline = current }
                capture(app, name: "Native stable ready \(landscape ? "landscape" : "portrait") \(mode)")
            }
        }
        app.terminate()
    }

    /// Run on a disposable simulator with fresh app preferences. Existing
    /// installations deliberately preserve their saved callsigns and accounts.
    @MainActor
    func testFreshGeneratedDefaultsAndReservedFeedbackStayStable() async throws {
        guard ProcessInfo.processInfo.environment["LEQRA_FRESH_INSTALL_UI"] == "1" else { throw XCTSkip("Requires a disposable fresh installation.") }
        try requireOnlineTestServer()
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let server = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"] ?? "http://127.0.0.1:18091"
        app.launchArguments = ["-serverURL", server, "--public-session-test-namespace", publicSessionTestNamespace, "--skip-public-session-restore"]
        app.launch()
        let field = app.textFields["callsignField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        app.buttons["openAccount"].tap()
        let reserved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Callsign:'")).firstMatch
        XCTAssertTrue(reserved.waitForExistence(timeout: 10), "First-open names must be claimed under a durably saved account key")
        app.buttons["Close Account key"].tap()
        let primary = try XCTUnwrap(field.value as? String)
        XCTAssertNotNil(primary.range(of: #"^(?:pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}|pilot-[a-z2-7]{10})$"#, options: .regularExpression))
        openPlayers(in: app)
        let add = app.buttons["addLocalP2"]; reveal(add, in: app); add.tap()
        XCTAssertTrue(app.textFields["localCallsignField"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.tap()
        let local = app.buttons["settingsLocalAccount"]
        for _ in 0..<5 where !local.isHittable { app.scrollViews["modalScroll"].swipeUp() }
        local.tap()
        XCTAssertTrue(app.staticTexts["accountPlayerIdentity"].waitForExistence(timeout: 5))
        let secondary = app.staticTexts["accountPlayerIdentity"].label.replacingOccurrences(of: " (P2)", with: "")
        XCTAssertNotEqual(primary, secondary)
        XCTAssertNotNil(secondary.range(of: #"^(?:pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}|pilot-[a-z2-7]{10})$"#, options: .regularExpression))
        XCTAssertTrue(reserved.waitForExistence(timeout: 10))
        app.buttons["Close Account key"].tap()
        app.buttons["Close Controls"].tap()
        var editing = false
        func replace(_ text: String) {
            if !editing {
                reveal(field, in: app)
                field.tap()
                field.press(forDuration: 1.1)
                let selectAll = app.menuItems["Select All"].exists ? app.menuItems["Select All"] : app.buttons["Select All"]
                if selectAll.exists { selectAll.tap() }
                editing = true
            }
            let old = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 1) + text)
        }
        replace("RUST")
        let controls = app.buttons["CONTROLS"].frame
        replace("Bot RUST")
        let feedback = app.staticTexts["callsignAvailability"]
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Reserved for bots.'"), object: feedback)
        await fulfillment(of: [rejected], timeout: 5)
        XCTAssertEqual(app.buttons["CONTROLS"].frame, controls, "The three-line advisory must reserve its layout before errors appear")
        XCTAssertFalse(app.buttons["Yours? Import account key"].isHittable, "A key cannot unlock the bot namespace")
        capture(app, name: "Native reserved callsign fixed three-line feedback")
        app.buttons["generateCallsign"].tap()
        let generated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH 'pilot#'"), object: field)
        await fulfillment(of: [generated], timeout: 10)
        app.scrollViews["readyRoomScroll"].swipeDown()
        XCUIDevice.shared.orientation = .landscapeLeft
        try await Task.sleep(nanoseconds: 700_000_000)
        capture(app, name: "Native generated room landscape")
        app.terminate()
    }

    /// A temporary localhost protocol fixture emits the real additive packet;
    /// no product debug flag or gameplay event is needed to preview a notice.
    @MainActor
    func testPassiveGodlikeBirthNoticeDoesNotShiftOrRepeat() async throws {
        guard let server = ProcessInfo.processInfo.environment["LEQRA_NOTICE_TEST_SERVER"] else { throw XCTSkip("Requires the temporary local notice fixture.") }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-serverURL", server, "-callsign", "NOTICE PILOT", "-localCallsign", "NOTICE P2",
                               "--public-session-test-namespace", publicSessionTestNamespace, "--skip-public-session-restore"]
        app.launch()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        selectPublic(true, in: app); play(in: app)
        let notice = app.staticTexts["godlikeSpawnNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "Bot 1 - Godlike spawned nearby. Watch out!")
        XCTAssertEqual(app.alerts.count, 0)
        let original = arena(in: app).frame
        capture(app, name: "Native passive Godlike birth portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(notice.exists)
        capture(app, name: "Native passive Godlike birth landscape")
        XCUIDevice.shared.orientation = .portrait
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(arena(in: app).frame, original)
        let expired = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
        await fulfillment(of: [expired], timeout: 10)
        XCTAssertEqual(arena(in: app).frame, original, "A passive overlay must never resize the arena")
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate()
    }

    /// Opt in with TEST_RUNNER_LEQRA_RENDER_STRESS_UI=1 when running xcodebuild.
    /// The deterministic workload stays offline and never changes room rules.
    @MainActor
    func testAllPowerUpsWithStackedBuffsKeepNativeControlsResponsive() throws {
        guard ProcessInfo.processInfo.environment["LEQRA_RENDER_STRESS_UI"] == "1" else {
            throw XCTSkip("Opt in to the ten-power-up native renderer stress matrix.")
        }
        XCUIDevice.shared.orientation = .portrait
        for power in ["rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman", "regular"] {
            let app = XCUIApplication()
            app.launchArguments = ["--native-performance-probe", "--probe-weapon", power,
                                   "--probe-bullets", "115", "--probe-buffs", "shield,speed,ghost", "--probe-pan"]
            if power == "regular" { app.launchArguments.append("--probe-bounces") }
            app.launch()
            XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15), power)
            XCTAssertTrue(app.staticTexts["pilotIdentity"].waitForExistence(timeout: 5), power)
            XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains("(P1)"), power)
            let stage = arena(in: app)
            XCTAssertTrue(app.frame.contains(stage.frame), power)
            let prefetched = expectation(description: power + " map prefetch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { prefetched.fulfill() }
            wait(for: [prefetched], timeout: 2)
            capture(app, name: "Native stacked-buff stress " + power + (power == "regular" ? " ricochets" : ""))
            pause(in: app)
            XCTAssertTrue(app.buttons["Resume"].isHittable, power)
            app.buttons["Resume"].tap()
            XCTAssertFalse(app.staticTexts["Paused"].exists, power)
            XCTAssertTrue(app.buttons["pauseGame"].isHittable, power)
            app.terminate()
        }
    }

    @MainActor
    func testAmmoDigitTransitionsKeepOutlinedCountsAboveEveryPowerIcon() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--native-performance-probe", "--probe-weapon", "rapid", "--probe-bullets", "115",
                               "--probe-buffs", "shield,speed", "--probe-badge-counts", "--probe-seconds", "8"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15))
        for frame in 0..<6 {
            try await Task.sleep(nanoseconds: 500_000_000)
            capture(app, name: "Outlined ammo transitions portrait \(frame)")
            XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        for frame in 0..<6 {
            try await Task.sleep(nanoseconds: 500_000_000)
            capture(app, name: "Outlined ammo transitions landscape \(frame)")
            XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        }
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate()
    }

    @MainActor
    private func hardwareKey(_ key: String, in app: XCUIApplication) {
        let physicalKey = key == XCUIKeyboardKey.escape.rawValue ? "\u{1B}" : key
        app.typeKey(physicalKey, modifierFlags: [])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.alerts.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 0.4), notNow.isHittable {
            let frame = notNow.frame
            springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            app.typeKey(physicalKey, modifierFlags: [])
        }
    }

    @MainActor
    private func p2InputState(_ stage: XCUIElement) -> [String: Double] {
        let value = stage.value as? String ?? ""
        return Dictionary(uniqueKeysWithValues: value.split(separator: ",").compactMap { item in
            let pair = item.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let number = Double(pair[1]) else { return nil }
            return (String(pair[0]), number)
        })
    }

    @MainActor
    private func launch(callsign: String? = nil, arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let server = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"] ?? "http://127.0.0.1:18081"
        // Argument-domain defaults override writes, so mutable settings are
        // deliberately read and restored inside the test instead.
        let name = callsign ?? "SWIFT FOX " + publicSessionTestNamespace.suffix(4).uppercased()
        app.launchArguments = ["-serverURL", server, "-callsign", name,
                               "--public-session-test-namespace", publicSessionTestNamespace,
                               "--skip-public-session-restore"] + arguments
        app.launch()
        let keyboardAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Not Now"]
        if keyboardAlert.exists, keyboardAlert.isHittable {
            let frame = keyboardAlert.frame
            XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        }
        XCTAssertTrue(app.switches["publicInfinityToggle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playRoom"].exists)
        return app
    }

    @MainActor
    func testAccountKeyIsMaskedInvalidImportsFailAndActiveGamesCannotSwitch() {
        let app = launch()
        let open = app.buttons["openAccount"]
        let primaryName = app.textFields["callsignField"].value as? String
        reveal(open, in: app); open.tap()
        XCTAssertTrue(app.staticTexts["maskedAccountKey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["maskedAccountKey"].label.contains("p_"))
        let draft = app.secureTextFields["importAccountKey"]
        XCTAssertTrue(draft.exists)
        XCTAssertTrue(draft.isEnabled)
        draft.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        draft.typeText("invalid-key")
        let check = app.buttons["checkAccountKey"]
        app.scrollViews["modalScroll"].swipeUp()
        XCTAssertTrue(check.isEnabled); check.tap()
        let error = app.staticTexts["accountImportStatus"]
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label.length > 0 AND label != 'Checking key…'"), object: error)
        XCTAssertEqual(XCTWaiter.wait(for: [rejected], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["useAccountKey"].exists, "An invalid key must never reach the replacement step.")
        let help = app.links["Open a GitHub issue"]
        for _ in 0..<5 where !help.isHittable { app.scrollViews["modalScroll"].swipeUp() }
        XCTAssertTrue(help.exists)
        app.buttons["Close Account key"].tap()
        if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }

        XCTAssertEqual(app.textFields["callsignField"].frame.midY, open.frame.midY, accuracy: 1, "Account access belongs beside its player's callsign.")
        let controls = app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch
        let closeControls = app.buttons["Close Controls"]
        let closeAccount = app.buttons["Close Account key"]
        let account = app.buttons["settingsAccount"]
        let localAccount = app.buttons["settingsLocalAccount"]
        controls.tap()
        XCTAssertEqual(account.label, "ACCOUNT KEY")
        XCTAssertFalse(localAccount.exists)
        reveal(account, in: app); account.tap()
        XCTAssertTrue(app.staticTexts["accountPlayerIdentity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["accountPlayerIdentity"].label.contains("(P1)"))
        XCTAssertTrue(closeAccount.isHittable, "Account Key is the active dialog.")
        closeAccount.tap()
        XCTAssertFalse(closeAccount.exists)
        XCTAssertTrue(closeControls.waitForExistence(timeout: 5))
        closeControls.tap()

        openPlayers(in: app)
        let add = app.buttons["addLocalP2"]; reveal(add, in: app); add.tap()
        XCTAssertTrue(app.textFields["localCallsignField"].waitForExistence(timeout: 5))
        controls.tap()
        XCTAssertEqual(account.label, "P1 ACCOUNT KEY")
        XCTAssertEqual(localAccount.label, "P2 ACCOUNT KEY")
        reveal(localAccount, in: app); localAccount.tap()
        XCTAssertTrue(app.staticTexts["accountPlayerIdentity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["accountPlayerIdentity"].label.contains("(P2)"))
        if app.staticTexts["maskedAccountKey"].label == "No account key saved on this device." {
            XCTAssertFalse(app.buttons["copyAccountKey"].isEnabled, "A missing P2 credential must never fall back to P1's key.")
        }
        closeAccount.tap()
        XCTAssertFalse(closeAccount.exists)
        XCTAssertTrue(closeControls.waitForExistence(timeout: 5))
        XCTAssertEqual(account.label, "P1 ACCOUNT KEY")
        closeControls.tap()
        XCTAssertEqual(app.textFields["callsignField"].value as? String, primaryName, "Managing P2 must not rename P1.")
        let remove = app.buttons["removeLocalP2"]
        if !remove.exists { openPlayers(in: app) }
        reveal(remove, in: app); remove.tap()
        controls.tap()
        XCTAssertEqual(account.label, "ACCOUNT KEY")
        XCTAssertFalse(localAccount.exists)
        closeControls.tap()

        selectPublic(false, in: app); selectMode("infinity", in: app); play(in: app); pause(in: app)
        app.buttons["Controls"].tap()
        for _ in 0..<5 where !account.isHittable { app.scrollViews["modalScroll"].swipeUp() }
        account.tap()
        XCTAssertTrue(app.secureTextFields["importAccountKey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["importAccountKey"].isEnabled)
        XCTAssertTrue(app.staticTexts["Return to the offline room to import or reset a key."].exists)
        closeAccount.tap()
        XCTAssertFalse(closeAccount.exists)
        XCTAssertTrue(closeControls.waitForExistence(timeout: 5))
        closeControls.tap()
        app.buttons["Resume"].tap()
        leaveGame(in: app)
    }

    @MainActor
    func testOfflineTouchPauseAndFrameRateSettings() {
        let app = launch()
        selectPublic(false, in: app)
        selectMode("infinity", in: app)
        play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains("SWIFT FOX"))
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains("(P1)"))
        exerciseControls(in: app)
        capture(app, name: "Native Infinity portrait controls")

        pause(in: app)
        let measured = app.staticTexts["frameRateValue"]
        XCTAssertTrue(measured.waitForExistence(timeout: 5))
        print("Native playing frame rate before pause: \(measured.label), \(measured.value ?? "")")
        app.buttons["Controls"].tap()
        let soundVolume = app.sliders["Sound volume"]
        let soundVolumeValue = app.staticTexts["soundVolumeValue"]
        XCTAssertTrue(soundVolume.waitForExistence(timeout: 5))
        XCTAssertTrue(soundVolumeValue.exists)
        guard let initialVolume = Int(soundVolumeValue.label.replacingOccurrences(of: "%", with: "")),
              (0...100).contains(initialVolume) else {
            XCTFail("Sound volume must expose a percentage between 0 and 100."); return
        }
        // A fresh-install job can assert the default without placing an
        // immutable argument-domain override over the user's preference.
        if let expected = ProcessInfo.processInfo.environment["LEQRA_EXPECT_INITIAL_SOUND_VOLUME"].flatMap(Int.init) {
            XCTAssertEqual(initialVolume, expected)
        }
        print("Initial native sound volume: \(initialVolume)%")
        // A retry after a failed gesture can restore the preference captured
        // by the first run, without changing the app's defaults domain.
        let restoreVolume = ProcessInfo.processInfo.environment["LEQRA_RESTORE_SOUND_VOLUME"].flatMap(Int.init) ?? initialVolume
        XCTAssertTrue((0...100).contains(restoreVolume))
        for percentage in [0, 100, restoreVolume] {
            soundVolume.adjust(toNormalizedSliderPosition: CGFloat(percentage) / 100)
            print("Sound volume adjustment requested \(percentage)%, label \(soundVolumeValue.label), slider \(soundVolume.value ?? "nil"), frame \(soundVolume.frame)")
            if soundVolumeValue.label != "\(percentage)%",
               let actual = Int(soundVolumeValue.label.replacingOccurrences(of: "%", with: "")) {
                // XCTest's normalized slider gesture can stop a few pixels
                // short of an endpoint. Drag the actual thumb past that edge.
                let width = soundVolume.frame.width
                let thumb = (15 + max(0, width - 30) * CGFloat(actual) / 100) / max(1, width)
                let target = percentage == 0 ? -0.04 : percentage == 100 ? 1.04
                    : (15 + max(0, width - 30) * CGFloat(percentage) / 100) / max(1, width)
                soundVolume.coordinate(withNormalizedOffset: CGVector(dx: thumb, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: soundVolume.coordinate(withNormalizedOffset: CGVector(dx: target, dy: 0.5)),
                           withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(percentage)%"), object: soundVolumeValue)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                           "Sound volume must reach \(percentage)% after adjusting its native slider; actual: \(soundVolumeValue.label).")
            XCTAssertTrue(app.buttons["Close Controls"].isHittable)
        }
        capture(app, name: "Native sound-volume settings")
        let highRate = app.switches["Request 120 FPS"]
        XCTAssertTrue(highRate.waitForExistence(timeout: 5))
        guard let initialRate = highRate.value as? String, ["0", "1"].contains(initialRate) else {
            XCTFail("A native frame-rate switch must expose its on/off state."); return
        }
        setSwitch(highRate, to: initialRate == "1" ? "0" : "1")
        setSwitch(highRate, to: initialRate)
        app.buttons["Close Controls"].tap()
        app.buttons["Resume"].tap()
        XCTAssertFalse(app.staticTexts["Paused"].exists)

        let enterFullscreen = app.buttons["Enter fullscreen"]
        XCTAssertTrue(enterFullscreen.isHittable)
        enterFullscreen.tap()
        XCTAssertTrue(app.buttons["Exit fullscreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.contains(arena(in: app).frame))
        XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        app.buttons["Exit fullscreen"].tap()
        XCTAssertTrue(enterFullscreen.waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        XCTAssertTrue(app.frame.contains(app.buttons["pauseGame"].frame))
        exerciseControls(in: app)
        print("Landscape app frame: \(app.frame), native arena: \(arena(in: app).frame)")
        capture(app, name: "Native Infinity landscape controls")
        pause(in: app)
        XCTAssertTrue(app.buttons["Resume"].isHittable)
        app.buttons["Resume"].tap()

        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        leaveGame(in: app)
        capture(app, name: "Native room")
    }

    @MainActor
    func testOfflineFixedModesUseNativeArenaAndReturnToReadyRoom() {
        let app = launch()
        selectPublic(false, in: app)
        for mode in ["elimination", "ctf", "koth", "survival"] {
            selectMode(mode, in: app)
            XCTAssertFalse(app.staticTexts["READY ROOM."].exists)
            XCTAssertFalse(app.staticTexts["arenaTitle"].exists)
            play(in: app)
            XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains("SWIFT FOX"))
            exerciseControls(in: app, fixedPortrait: true)
            capture(app, name: "Native \(mode) arena")
            leaveGame(in: app)
        }
    }

    @MainActor
    func testPublicInfinityStandingsAndLeave() throws {
        try requireOnlineTestServer()
        let app = launch()
        selectPublic(true, in: app)
        play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains("SWIFT FOX"))
        capture(app, name: "Native public Infinity")
        let leaderboard = app.buttons.matching(NSPredicate(format: "label == 'LEADERBOARD'")).firstMatch
        leaderboard.tap()
        XCTAssertTrue(app.staticTexts["+1 per kill, -1 per death"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pauseGame"].isHittable)
        capture(app, name: "Native in-arena public standings")
        leaderboard.tap()
        XCTAssertFalse(app.staticTexts["+1 per kill, -1 per death"].exists)
        leaveGame(in: app)
    }

    /// Run alone against a fresh disposable database so this unique pilot
    /// appears in the public top ten. The separate Keychain service never touches a user's
    /// normal recovery credential, even on a connected physical device.
    @MainActor
    func testPublicInfinityColdRelaunchRestoresIdentityAndExitStopsAutomaticRejoin() async throws {
        guard ProcessInfo.processInfo.environment["LEQRA_PUBLIC_RECOVERY_UI"] == "1" else {
            throw XCTSkip("Opt in to authenticated public Infinity cold-launch recovery.")
        }
        try requireOnlineTestServer()
        try await prepareRunnerLocalNetworkAccess()
        let name = "REC " + UUID().uuidString.prefix(8).uppercased()
        let app = launch(callsign: name)
        let namespaceIndex = try XCTUnwrap(app.launchArguments.firstIndex(of: "--public-session-test-namespace")) + 1
        let otherNamespace = publicSessionTestNamespace + "-other"
        defer {
            app.terminate()
            app.launchArguments += ["--skip-public-session-restore", "--reset-public-session-test-store"]
            for namespace in [publicSessionTestNamespace, otherNamespace] {
                app.launchArguments[namespaceIndex] = namespace
                app.launch()
                _ = app.buttons["playRoom"].waitForExistence(timeout: 10)
                app.terminate()
            }
        }
        selectPublic(true, in: app)
        play(in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Authenticated recovery requires successful Keychain storage; use a signed simulator build.")
        let original = try await publicLeader(named: name)
        app.terminate()

        app.launchArguments.removeAll { $0 == "--skip-public-session-restore" }
        app.launch()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 20), "An active public session must reopen without tapping PLAY.")
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(name))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let recovered = try await publicLeader(named: name)
        XCTAssertEqual(recovered.id, original.id, "The Keychain bearer must recover the original identity; matching callsigns do not authenticate.")

        leaveGame(in: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10), "Explicit Exit must clear automatic-rejoin intent.")
        XCTAssertFalse(app.buttons["pauseGame"].exists)
        selectPublic(true, in: app)
        play(in: app)
        let deliberateRejoin = try await publicLeader(named: name)
        XCTAssertEqual(deliberateRejoin.id, original.id, "Explicit Exit retains the authenticated identity for a later deliberate PLAY.")
        leaveGame(in: app)

        app.terminate()
        app.launchArguments[namespaceIndex] = otherNamespace
        app.launch()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        let fieldFrame = app.textFields["callsignField"].frame
        let feedback = app.staticTexts["callsignAvailability"]
        let taken = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Used online'"), object: feedback)
        await fulfillment(of: [taken], timeout: 10)
        XCTAssertEqual(app.textFields["callsignField"].frame, fieldFrame, "Inline validation must reserve its space.")
        selectPublic(false, in: app)
        selectMode("infinity", in: app)
        play(in: app)
        XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains(name), "Offline play permits a callsign claimed by another online owner.")
        leaveGame(in: app)
        selectPublic(true, in: app)
        app.buttons["playRoom"].tap()
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Used online'"), object: feedback)
        await fulfillment(of: [rejected], timeout: 15)
        XCTAssertTrue(app.buttons["playRoom"].exists)
        XCTAssertFalse(app.buttons["pauseGame"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "An online name conflict belongs beside the callsign editor.")
    }

    private struct PublicLeader {
        let id: Int
    }

    @MainActor
    private func prepareRunnerLocalNetworkAccess() async throws {
        #if !targetEnvironment(simulator)
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"])
        let base = try XCTUnwrap(URL(string: address))
        let runnerID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let runner = XCUIApplication(bundleIdentifier: runnerID)
        runner.activate()
        XCTAssertTrue(runner.wait(for: .runningForeground, timeout: 5))

        // iOS cannot present the runner's first local-network prompt while
        // leqra is in front. Establish this permission before testing recovery.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let endpoint = base.appendingPathComponent("api/build")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for attempt in 0..<3 {
            let request = Task { try await session.data(from: endpoint) }
            await Task.yield()
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 2),
               alert.label.localizedCaseInsensitiveContains("local network")
                || alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'local network'")).count > 0 {
                let allow = alert.buttons["Allow"]
                XCTAssertTrue(allow.exists, "The runner's local-network prompt must offer Allow.")
                if allow.exists { allow.tap() }
            }
            do {
                let (_, response) = try await request.value
                let http = try XCTUnwrap(response as? HTTPURLResponse)
                XCTAssertEqual(http.statusCode, 200, "The UI test runner must reach the disposable server.")
                return
            } catch let error as URLError where attempt < 2
                && [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
                // The first request can fail before the permission is granted.
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        #endif
    }

    @MainActor
    private func publicLeader(named name: String) async throws -> PublicLeader {
        let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"] ?? "http://127.0.0.1:18081"
        let base = try XCTUnwrap(URL(string: address))
        let endpoint = base.appendingPathComponent("api/infinity")
        let deadline = Date().addingTimeInterval(10)
        repeat {
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if let leaders = object["leaders"] as? [[String: Any]],
               let leader = leaders.first(where: { $0["name"] as? String == name }), let id = leader["id"] as? Int {
                return PublicLeader(id: id)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        XCTFail("The unique recovery pilot must appear in the disposable server's public standings.")
        throw NSError(domain: "leqraUITests", code: 1)
    }

    @MainActor
    func testPrivateInfinityReturnsToRoomWithLocalIdentityThenStartsFixedMatch() throws {
        try requireOnlineTestServer()
        let app = launch()
        selectPublic(false, in: app)
        selectMode("infinity", in: app)
        let share = app.buttons["SHARE ROOM ONLINE ↗"]
        reveal(share, in: app)
        share.tap()
        XCTAssertTrue(app.staticTexts["roomCodeValue"].waitForExistence(timeout: 15), "The local Go server must be listening on port 18081.")
        let roomCode = app.staticTexts["roomCodeValue"].label
        selectPublic(false, in: app)
        openPlayers(in: app)
        XCTAssertTrue(app.staticTexts["localRoomIdentity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["localRoomIdentity"].label.contains("SWIFT FOX"))
        reveal(app.buttons["Add bot"], in: app)
        app.buttons["Add bot"].tap()
        play(in: app)
        capture(app, name: "Native private Infinity portrait")
        pause(in: app)
        reveal(app.buttons["Leave game"], in: app)
        app.buttons["Leave game"].tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["roomCodeValue"].exists, "Exiting Infinity must retain its source private room.")
        XCTAssertEqual(app.staticTexts["roomCodeValue"].label, roomCode)
        openPlayers(in: app)
        XCTAssertTrue(app.staticTexts["localRoomIdentity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["localRoomIdentity"].label.contains("SWIFT FOX"))
        play(in: app)
        pause(in: app)
        app.buttons["Return to room"].tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        openPlayers(in: app)
        XCTAssertTrue(app.staticTexts["localRoomIdentity"].waitForExistence(timeout: 5), "Room IDs must be restored after Infinity assigns its arena tank ID.")

        selectMode("elimination", in: app)
        play(in: app)
        capture(app, name: "Native online fixed-maze match")
        pause(in: app)
        app.buttons["Return to room"].tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 10))
        openPlayers(in: app)
        XCTAssertTrue(app.staticTexts["localRoomIdentity"].waitForExistence(timeout: 5))
        reveal(app.buttons["Leave room"], in: app)
        app.buttons["Leave room"].tap()
        XCTAssertTrue(app.switches["publicInfinityToggle"].waitForExistence(timeout: 5))
    }

    private func requireOnlineTestServer() throws {
        #if !targetEnvironment(simulator)
        guard let server = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"],
              !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Physical-device online tests require LEQRA_TEST_SERVER.")
        }
        #endif
    }

    @MainActor
    private func selectPublic(_ enabled: Bool, in app: XCUIApplication) {
        let toggle = app.switches["publicInfinityToggle"]
        reveal(toggle, in: app)
        let target = enabled ? "1" : "0"
        if toggle.value as? String != target { setSwitch(toggle, to: target) }
    }

    @MainActor
    private func selectMode(_ mode: String, in app: XCUIApplication) {
        let choice = app.buttons["mode_" + mode]
        if !choice.exists {
            let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Room settings'")).firstMatch
            reveal(settings, in: app)
            settings.tap()
        }
        reveal(choice, in: app)
        choice.tap()
    }

    @MainActor
    private func openPlayers(in app: XCUIApplication) {
        guard !app.staticTexts["localRoomIdentity"].exists else { return }
        let players = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Players and bots'")).firstMatch
        reveal(players, in: app)
        players.tap()
    }

    @MainActor
    private func play(in app: XCUIApplication) {
        let button = app.buttons["playRoom"]
        reveal(button, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        button.tap()
        XCTAssertTrue(app.buttons["pauseGame"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["pilotIdentity"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func pause(in app: XCUIApplication) {
        app.buttons["pauseGame"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func leaveGame(in app: XCUIApplication) {
        pause(in: app)
        reveal(app.buttons["Leave game"], in: app)
        app.buttons["Leave game"].tap()
        XCTAssertTrue(app.buttons["playRoom"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func arena(in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)["arenaStage"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(element.frame.width, 100)
        XCTAssertGreaterThan(element.frame.height, 100)
        return element
    }

    @MainActor
    private func exerciseControls(in app: XCUIApplication, fixedPortrait: Bool = false) {
        let frame = arena(in: app).frame
        let bottom = fixedPortrait ? 59.5 : 67.5
        let stickX = frame.minX + (fixedPortrait ? 93 : 84)
        let fireX = frame.maxX - (fixedPortrait ? 85.5 : 63.5)
        let y = frame.maxY - bottom
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let stick = origin.withOffset(CGVector(dx: stickX, dy: y))
        let target = origin.withOffset(CGVector(dx: stickX + 25, dy: y - 25))
        XCTAssertTrue(app.frame.contains(CGPoint(x: stickX, y: y)))
        XCTAssertTrue(app.frame.contains(CGPoint(x: fireX, y: y)))
        stick.press(forDuration: 0.05, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.2)
        origin.withOffset(CGVector(dx: fireX, dy: y)).press(forDuration: 0.2)
        XCTAssertTrue(app.buttons["pauseGame"].isHittable)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let modal = app.scrollViews["modalScroll"]
        let ready = app.scrollViews["readyRoomScroll"]
        let pause = app.scrollViews["pauseMenuScroll"]
        let scroll = modal.exists ? modal : pause.exists ? pause : ready.exists ? ready : app
        for attempt in 0..<8 {
            let before = element.frame
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 4, dy: 8)
            guard !viewport.isEmpty else { break }
            if element.isHittable && viewport.contains(before) { return }
            if scroll.frame.insetBy(dx: -1, dy: -1).contains(before) { return }
            if viewport.contains(before) {
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
                if XCTWaiter.wait(for: [settled], timeout: 1) == .completed { return }
                print("Visible but not hittable: \(element.identifier), element \(before), viewport \(viewport)")
                capture(app, name: "Visible but unreachable " + element.identifier)
                break
            }
            let upward = before.midY > viewport.midY
            let distance = min(viewport.height * 0.48, max(65, abs(before.midY - viewport.midY)))
            // Use the card's empty left padding. Centered swipes can begin on
            // a field; right-edge drags can grab the native scroll indicator
            // and move the content in the opposite direction.
            let x = viewport.minX + min(14, viewport.width / 6)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let startY = viewport.midY + (upward ? distance / 2 : -distance / 2)
            let endY = viewport.midY - (upward ? distance / 2 : -distance / 2)
            origin.withOffset(CGVector(dx: x, dy: startY))
                .press(forDuration: 0.08, thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.15)
            print("Reveal \(attempt) \(element.identifier), before \(before), after \(element.frame), hittable \(element.isHittable), viewport \(viewport)")
        }
        if !element.isHittable { print("Unreachable element: \(element.debugDescription), frame \(element.frame), scroll \(scroll.frame)") }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // Application screenshots can crop a rotated UIKit window using its
        // portrait backing dimensions. Capture the display to retain the full
        // native landscape surface, including controls at both screen edges.
        let screenshot = XCUIScreen.main.screenshot()
        let raster = screenshot.image
        print("Screenshot \(name): app \(app.frame), image \(raster.size), pixels \(raster.cgImage?.width ?? 0)x\(raster.cgImage?.height ?? 0), orientation \(raster.imageOrientation.rawValue)")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let changed = expectation(for: NSPredicate { _, _ in
            (app.frame.width > app.frame.height) == landscape
        }, evaluatedWith: nil)
        wait(for: [changed], timeout: 10)
        let showcase = app.descendants(matching: .any)["showcaseStage"].firstMatch
        let split = app.descendants(matching: .any)["secondaryArenaStage"].firstMatch
        let stage = showcase.exists ? showcase : app.descendants(matching: .any)["arenaStage"].firstMatch
        guard stage.exists, !app.scrollViews["modalScroll"].exists else { return }
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (split.exists || (stage.frame.width > stage.frame.height) == landscape) && app.frame.contains(stage.frame)
        }, object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed)
    }

    @MainActor
    private func setSwitch(_ element: XCUIElement, to value: String) {
        let descendant = element.switches.firstMatch
        let control = descendant.exists ? descendant : element
        print("Toggling native switch from \(element.value ?? "nil") to \(value), frame \(control.frame)")
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "The switch must change after tapping its native thumb; actual value: \(element.value ?? "nil")")
    }
}
