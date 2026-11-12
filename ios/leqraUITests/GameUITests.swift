import XCTest

/// Online smoke tests use `PORT=18081 go run ./src` on the simulator host.
/// Physical-device online tests can supply LEQRA_TEST_SERVER with a LAN URL.
/// Screenshots are XCTest attachments, never repository artifacts.
final class GameUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let server = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"] ?? "http://127.0.0.1:18081"
        // Argument-domain defaults override writes, so mutable settings are
        // deliberately read and restored inside the test instead.
        app.launchArguments = ["-serverURL", server, "-callsign", "SWIFT FOX"]
        app.launch()
        XCTAssertTrue(app.switches["publicInfinityToggle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playRoom"].exists)
        return app
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
        app.buttons["Settings"].tap()
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
            XCTAssertTrue(app.buttons["Done"].isHittable)
        }
        capture(app, name: "Native sound-volume settings")
        let highRate = app.switches["Request 120 FPS"]
        XCTAssertTrue(highRate.waitForExistence(timeout: 5))
        guard let initialRate = highRate.value as? String, ["0", "1"].contains(initialRate) else {
            XCTFail("A native frame-rate switch must expose its on/off state."); return
        }
        setSwitch(highRate, to: initialRate == "1" ? "0" : "1")
        setSwitch(highRate, to: initialRate)
        app.buttons["Done"].tap()
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
        capture(app, name: "Native ready room")
    }

    @MainActor
    func testOfflineFixedModesUseNativeArenaAndReturnToReadyRoom() {
        let app = launch()
        selectPublic(false, in: app)
        for mode in ["elimination", "ctf", "koth", "survival"] {
            selectMode(mode, in: app)
            play(in: app)
            XCTAssertTrue(app.staticTexts["pilotIdentity"].label.contains("SWIFT FOX"))
            exerciseControls(in: app, fixedPortrait: true)
            capture(app, name: "Native \(mode) arena")
            leaveGame(in: app)
        }
    }

    @MainActor
    func testPublicInfinityStandingsAndLeave() {
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

    @MainActor
    func testPrivateInfinityReturnsToRoomWithLocalIdentityThenStartsFixedMatch() {
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
        let ready = app.scrollViews["readyRoomScroll"]
        let pause = app.scrollViews["pauseMenuScroll"]
        let scroll = pause.exists ? pause : ready.exists ? ready : app
        for attempt in 0..<8 {
            if element.isHittable { return }
            let before = element.frame
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 4, dy: 8)
            guard !viewport.isEmpty else { break }
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
        let stage = arena(in: app)
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (stage.frame.width > stage.frame.height) == landscape && app.frame.contains(stage.frame)
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
