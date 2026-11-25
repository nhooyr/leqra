import XCTest

final class MacCatalystUITests: XCTestCase {
    @MainActor
    func testDesktopSettingsExposeKeyboardAndMouseControls() {
        let app = launch()
        defer { app.terminate() }
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.click()
        let sound = app.descendants(matching: .any)["settingSound"].firstMatch
        let originalSound = sound.value as? String
        XCTAssertNotNil(originalSound)
        app.buttons["Close Controls"].click()
        let callsign = app.textFields["callsignField"]
        callsign.click()
        callsign.typeKey("a", modifierFlags: .command)
        callsign.typeText("PMPilot")
        XCTAssertEqual(callsign.value as? String, "PMPilot")
        XCTAssertFalse(app.staticTexts["Paused"].exists)
        app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.click()
        XCTAssertEqual(sound.value as? String, originalSound, "Typing M must not toggle sound")
        for identifier in ["settingMouseAim", "settingMouseFire", "bind0_forward", "bind1_forward"] {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
        }
        for identifier in ["settingMouseAim", "settingMouseFire"] {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            reveal(control, in: app)
            let original = control.value as? String
            XCTAssertNotNil(original)
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            waitUntil("The mouse setting responds to a click") { control.value as? String != original }
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            waitUntil("The mouse setting is restored") { control.value as? String == original }
        }
        let binding = app.buttons["bind0_forward"]
        reveal(binding, in: app)
        binding.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["Press a key"].waitForExistence(timeout: 5))
        app.windows.firstMatch.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        waitUntil("Escape closes the key capture") { !app.staticTexts["Press a key"].exists }
        XCTAssertTrue(app.buttons["Close Controls"].exists, "Escape cancels capture without closing Controls")
        XCTAssertTrue(binding.exists)
        capture(app, name: "Mac keyboard and mouse settings")
    }

    @MainActor
    func testEscapeDismissesReadyRoomLeaderboard() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["toggleStandings"].click()
        let close = app.buttons["closeStandings"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.windows.firstMatch.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        waitUntil("Escape closes the ready-room leaderboard") { !close.exists }
        XCTAssertTrue(app.buttons["playRoom"].exists)
        XCTAssertFalse(app.buttons["pauseGame"].exists)
    }

    @MainActor
    func testKeyboardMovementMouseAimAndFire() throws {
        for fixed in [true, false] {
            let app = launch(probe: true, fixed: fixed)
            defer { app.terminate() }
            if fixed {
                app.buttons.matching(NSPredicate(format: "label == 'Controls'")).firstMatch.click()
                let turn = app.buttons["bind0_right"]
                reveal(turn, in: app)
                turn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
                XCTAssertTrue(app.staticTexts["Press a key"].waitForExistence(timeout: 5))
                app.windows.firstMatch.typeKey(XCUIKeyboardKey.shift, modifierFlags: [])
                waitUntil("Turn right is remapped to Shift for simultaneous keyboard input") {
                    !app.staticTexts["Press a key"].exists && turn.label.contains("SHIFT L")
                }
                app.buttons["Close Controls"].click()
            }
            let stage = arena(app)
            let before = values(stage)
            XCTAssertEqual(before["touchControls"], 0, "Desktop gameplay does not show touch controls")
            stage.click()
            if fixed {
                for _ in 0..<16 { stage.typeKey("w", modifierFlags: []) }
                waitUntil("Keyboard movement changes the tank position") {
                    let moved = self.values(stage)
                    return hypot(
                        (moved["x"] ?? 0) - (before["x"] ?? 0), (moved["y"] ?? 0) - (before["y"] ?? 0))
                        > 0.5
                }
            }
            let position = values(stage)
            let viewWidth = try XCTUnwrap(position["viewWidth"])
            let viewHeight = try XCTUnwrap(position["viewHeight"])
            let targetX = (position["screenX"] ?? 0) + 110
            let targetY = (position["screenY"] ?? 0) - 75
            let target = stage.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: targetX / viewWidth, dy: targetY / viewHeight))
            target.hover()
            var expected = atan2(-75.0, 110.0)
            print(
                "MAC POINTER fixed=\(fixed) window=\(app.windows.firstMatch.frame) arena=\(stage.frame) before=\(position) hovered=\(values(stage))"
            )
            capture(app, name: "Mac \(fixed ? "fixed" : "Infinity") pointer aim")
            waitUntil("Pointer movement aims the turret") {
                abs(self.angleDifference(self.values(stage)["angle"] ?? 99, expected)) < 0.12
            }
            if fixed {
                let beforeDrive = values(stage)
                for _ in 0..<32 { stage.typeKey("w", modifierFlags: .shift) }
                waitUntil("The tank drives while the pointer stays still") {
                    let moved = self.values(stage)
                    return hypot(
                        (moved["x"] ?? 0) - (beforeDrive["x"] ?? 0),
                        (moved["y"] ?? 0) - (beforeDrive["y"] ?? 0)) > 0.5
                }
                let moved = values(stage)
                let movingAim = atan2(targetY - (moved["screenY"] ?? 0), targetX - (moved["screenX"] ?? 0))
                XCTAssertGreaterThan(abs(angleDifference(movingAim, expected)), 0.02)
                expected = movingAim
                waitUntil("A stationary pointer keeps aiming at its screen position while driving") {
                    abs(self.angleDifference(self.values(stage)["angle"] ?? 99, movingAim)) < 0.02
                }
            }
            let priorShot = values(stage)["shotID"] ?? 0
            target.click()
            waitUntil("Primary mouse click fires immediately") {
                (self.values(stage)["shotID"] ?? 0) > priorShot
            }
            let shot = values(stage)
            // The fixed fixture has no walls; Infinity rounds can ricochet during click synthesis.
            if fixed {
                XCTAssertLessThan(
                    abs(angleDifference(atan2(shot["shotVY"] ?? 0, shot["shotVX"] ?? 0), expected)), 0.15)
            }
            capture(app, name: "Mac \(fixed ? "fixed" : "Infinity") keyboard and mouse")
            app.terminate()
        }
    }

    @MainActor
    func testPairedDesktopKeyboardAndHoveredMouseStayIndependent() {
        let app = launch(arguments: ["--probe-local-p2-input"])
        defer { app.terminate() }
        let publicToggle = app.descendants(matching: .any)["publicInfinityToggle"].firstMatch
        if publicToggle.value as? String == "1" { publicToggle.click() }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Players and bots'")).firstMatch.click()
        let addP2 = app.buttons["addLocalP2"]
        reveal(addP2, in: app)
        addP2.click()
        XCTAssertTrue(
            app.staticTexts["Keyboard layout 1 controls P1. Keyboard layout 2 controls P2."]
                .waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Touch controls P1. Keyboard/mouse controls P2."].exists)
        let removeBots = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '"))
        while removeBots.count > 0 {
            let remove = removeBots.firstMatch
            reveal(remove, in: app)
            remove.click()
        }
        let mode = app.buttons["mode_infinity"]
        if !mode.exists {
            let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Room settings'"))
                .firstMatch
            reveal(settings, in: app)
            settings.click()
        }
        reveal(mode, in: app)
        mode.click()
        let randomBots = app.descendants(matching: .any)["randomRoamingBots"].firstMatch
        if randomBots.exists, randomBots.value as? String == "1" {
            reveal(randomBots, in: app)
            randomBots.click()
        }
        let play = app.buttons["playRoom"]
        reveal(play, in: app)
        play.click()
        let primary = app.descendants(matching: .any)["arenaStage"].firstMatch
        let secondary = app.descendants(matching: .any)["secondaryArenaStage"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertTrue(secondary.waitForExistence(timeout: 5))
        waitUntil("Both pilot diagnostics are ready") { self.values(primary)["p2a"] != nil }
        primary.click()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).hover()
        let before = settledValues(primary, angles: ["p1a", "p2a"])
        for _ in 0..<16 { primary.typeKey("d", modifierFlags: []) }
        waitUntil("WASD rotates P1") {
            abs(self.angleDifference(self.values(primary)["p1a"] ?? 0, before["p1a"] ?? 0)) > 0.01
        }
        let wasd = settledValues(primary, angles: ["p1a", "p2a"])
        XCTAssertEqual(wasd["p2a"] ?? 0, before["p2a"] ?? 0, accuracy: 0.001)
        for _ in 0..<16 { primary.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: []) }
        waitUntil("Arrow keys rotate P2") {
            abs(self.angleDifference(self.values(primary)["p2a"] ?? 0, wasd["p2a"] ?? 0)) > 0.01
        }
        let arrows = settledValues(primary, angles: ["p1a", "p2a"])
        XCTAssertEqual(arrows["p1a"] ?? 0, wasd["p1a"] ?? 0, accuracy: 0.001)
        secondary.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.25)).hover()
        waitUntil("The hovered second viewport aims P2") {
            abs(self.angleDifference(self.values(primary)["p2a"] ?? 0, arrows["p2a"] ?? 0)) > 0.1
        }
        let hover = settledValues(primary, angles: ["p1a", "p2a"])
        XCTAssertEqual(hover["p1a"] ?? 0, arrows["p1a"] ?? 0, accuracy: 0.001)
        capture(app, name: "Mac independent P1 and P2 controls")
    }

    @MainActor
    func testBackgroundReturnDoesNotLeaveMovementLatched() {
        let app = launch(probe: true, fixed: true)
        defer { app.terminate() }
        let stage = arena(app)
        stage.click()
        for _ in 0..<8 { stage.typeKey("w", modifierFlags: []) }
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        app.activate()
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        let returned = values(stage)
        let stable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let current = self.values(stage)
                return hypot(
                    (current["x"] ?? 0) - (returned["x"] ?? 0), (current["y"] ?? 0) - (returned["y"] ?? 0))
                    > 0.5
            }, object: stage)
        stable.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 0.5), .completed)
    }

    @MainActor
    func testWindowResizePreservesArenaAndEscapePauses() {
        let app = launch(probe: true, fixed: true)
        defer { app.terminate() }
        let stage = arena(app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        let before = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(
            CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.15, thenDragTo: corner.withOffset(CGVector(dx: -180, dy: -120)))
        waitUntil("The native window resizes") { abs(window.frame.width - before.width) > 40 }
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(stage.frame))
        XCTAssertGreaterThan(stage.frame.width, 300)
        XCTAssertGreaterThan(stage.frame.height, 200)
        stage.click()
        stage.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        app.buttons["Resume"].click()
        waitUntil("Resume restores the arena") { !app.staticTexts["Paused"].exists && stage.exists }
        capture(app, name: "Mac resized gameplay")
    }

    @MainActor
    private func launch(probe: Bool = false, fixed: Bool = false, arguments: [String] = []) -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "-serverURL", "http://127.0.0.1:1", "--public-session-test-namespace", "mac-" + UUID().uuidString,
            "--reset-public-session-test-store", "--skip-public-session-restore", "-callsign", "MAC TEST",
            "-localCallsign", "MAC WING",
        ]
        if probe { app.launchArguments.append("--probe-direct-aim") }
        if fixed { app.launchArguments.append("--probe-fixed") }
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(
            (probe ? app.buttons["pauseGame"] : app.buttons["playRoom"]).waitForExistence(timeout: 10))
        app.activate()
        print("MAC UI window \(app.windows.firstMatch.frame)")
        return app
    }

    @MainActor
    private func arena(_ app: XCUIApplication) -> XCUIElement {
        let stage = app.descendants(matching: .any)["arenaStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        waitUntil("Arena diagnostics are ready") { self.values(stage)["screenX"] != nil }
        return stage
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.containing(.any, identifier: element.identifier).firstMatch
        for _ in 0..<10 where !scroll.frame.contains(element.frame) {
            let delta: CGFloat = element.frame.midY < scroll.frame.midY ? 180 : -180
            print(
                "MAC SCROLL \(element.identifier) element=\(element.frame) viewport=\(scroll.frame) delta=\(delta)"
            )
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).scroll(
                byDeltaX: 0, deltaY: delta)
        }
        XCTAssertTrue(scroll.frame.contains(element.frame))
    }

    @MainActor
    private func values(_ element: XCUIElement) -> [String: Double] {
        Dictionary(
            uniqueKeysWithValues: (element.value as? String ?? "").split(separator: ",").compactMap {
                let pair = $0.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, let value = Double(pair[1]) else { return nil }
                return (String(pair[0]), value)
            })
    }

    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a - b), cos(a - b))
    }

    @MainActor
    private func settledValues(_ element: XCUIElement, angles: [String]) -> [String: Double] {
        var previous = values(element)
        var stable = 0
        waitUntil("Released controls finish their turn easing") {
            let current = self.values(element)
            if angles.allSatisfy({ abs(self.angleDifference(current[$0] ?? 0, previous[$0] ?? 0)) < 0.0001 })
            {
                stable += 1
            } else {
                stable = 0
            }
            previous = current
            return stable >= 2
        }
        return previous
    }

    @MainActor
    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, description)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class MacCatalystOnlineUITests: XCTestCase {
    @MainActor
    func testPublicInfinityReceivesServerState() throws {
        let server = try XCTUnwrap(
            ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"],
            "Run this regression test explicitly with a disposable LEQRA_TEST_SERVER.")
        let app = XCUIApplication()
        app.launchArguments = [
            "-serverURL", server, "-callsign", "MAC " + UUID().uuidString.prefix(8),
            "--public-session-test-namespace", "mac-online-" + UUID().uuidString,
            "--reset-public-session-test-store", "--skip-public-session-restore", "--probe-muzzle-device",
        ]
        app.launch()
        defer { app.terminate() }
        let publicToggle = app.descendants(matching: .any)["publicInfinityToggle"].firstMatch
        XCTAssertTrue(publicToggle.waitForExistence(timeout: 10))
        if publicToggle.value as? String != "1" { publicToggle.click() }
        let play = app.buttons["playRoom"]
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        play.click()
        let stage = app.descendants(matching: .any)["arenaStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        let connected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let state = self.values(stage)
                return state["online"] == 1 && state["connected"] == 1 && (state["tick"] ?? 0) > 0
            }, object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 10), .completed)
        let tick = values(stage)["tick"] ?? 0
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (self.values(stage)["tick"] ?? 0) > tick + 2 }, object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Mac real online Public Infinity"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func values(_ element: XCUIElement) -> [String: Double] {
        Dictionary(
            uniqueKeysWithValues: (element.value as? String ?? "").split(separator: ",").compactMap {
                let pair = $0.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, let value = Double(pair[1]) else { return nil }
                return (String(pair[0]), value)
            })
    }
}
