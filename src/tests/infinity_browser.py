"""Exercise Infinity in Chromium against a dedicated leqra server.

Start the current server with `go run ./src`, then run
`python3 src/tests/infinity_browser.py [http://localhost:8080]`.
LEQRA_URL can supply the URL. Install Playwright and Chromium first.
"""

import argparse
import json
import os
from pathlib import Path
import re
from urllib.parse import quote

from playwright.sync_api import expect, sync_playwright


def load(context, url, name, errors):
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script(f"""
        try {{
            localStorage.setItem('leqra.name', {json.dumps(name)});
            localStorage.setItem('leqra.introTour.v1', '1');
        }} catch {{}}
    """)
    page.goto(url)
    page.wait_for_function("() => !!window.leqraInfinity")
    return page


def select_room_infinity(page):
    settings = page.locator("#roomSettings")
    settings.locator("summary").click()
    mode = settings.locator('[data-room-mode="infinity"]')
    mode.click()
    expect(mode).to_have_attribute("aria-checked", "true")


def expect_pilots(page, count):
    expect(page.locator("#infiniteArena")).to_be_visible()
    expect(page.locator("#infiniteStatus")).to_contain_text(re.compile(rf"\b{count} online\b"))


def expect_score_rank(page, split=False):
    score = r"-?\d+ \(#[1-9]\d*\)"
    pattern = rf"^P1 {score} · P2 {score}$" if split else rf"^Score {score}$"
    expect(page.locator("#infiniteKills")).to_have_text(re.compile(pattern))


def standings(page):
    panel = page.locator("#infiniteLeaderboardPanel")
    if panel.get_attribute("open") is None:
        panel.locator("summary").press("Space")
    expect(panel).to_have_attribute("open", "")
    return panel.locator("#infiniteLeaderboard")


def is_packet(frame, kind, **fields):
    if not isinstance(frame, str):
        return False
    packet = json.loads(frame)
    return packet.get("type") == kind and all(packet.get(key, False) == value for key, value in fields.items())


def check_pause_style(page, online):
    pause = page.locator("#infinitePauseMenu")
    assert pause.evaluate("dialog => dialog.matches(':modal')")
    card = pause.locator(".screen-card")
    fixed = page.locator("#onlineMenuScreen" if online else "#pauseScreen")
    heading = card.get_by_role("heading", name="STAY CONNECTED." if online else "HOLD YOUR FIRE.", exact=True)
    back = card.get_by_role("button", name="BACK TO THE ARENA" if online else "BACK TO THE BATTLE", exact=True)
    expect(heading).to_be_visible()
    expect(back).to_be_focused()
    message = card.locator("p").filter(has_text="respawning waits" if online else "Your tank is safe")
    expect(message).to_be_visible()
    sidebar = pause.locator("#infinitePauseSidebar #gameSidebar")
    expect(sidebar).to_be_visible()
    expect(sidebar.locator("#infiniteLeaderboardPanel")).to_have_attribute("open", "")
    expect(sidebar.locator("#manualContent .warning")).to_contain_text("INFINITY")
    expect(sidebar.locator(".power-row")).to_have_count(10)
    expect(sidebar.locator(".power-note")).to_contain_text("Starman lasts 8 seconds")
    expect(sidebar.locator(".power-row").filter(has_text="Cannon")).to_contain_text("5.3s flight")
    expect(sidebar.locator(".fixed-maze-panel")).to_be_hidden()
    expect(sidebar.locator(".log-panel")).to_be_hidden()

    def style(locator, properties):
        return locator.evaluate("""(node, properties) => {
            const computed = getComputedStyle(node);
            return properties.map(name => computed.getPropertyValue(name));
        }""", properties)

    for actual, reference, properties in (
        (card, fixed, ["background-image", "border-radius", "box-shadow"]),
        (heading, fixed.locator(".compact-title"), ["font-weight", "font-family"]),
        (back, fixed.locator(".back-action"), ["background-color", "border-radius", "font-weight"]),
    ):
        actual_style, reference_style = style(actual, properties), style(reference, properties)
        assert actual_style == reference_style, (properties, actual_style, reference_style)


def check_online_pause(page, socket):
    arena = page.locator("#infiniteArena")
    pause = page.locator("#infinitePauseMenu")
    resume = pause.locator("#infiniteResumeBtn")
    canvas = page.locator("#infiniteCanvas")
    canvas.focus()
    with socket.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", forward=True)):
        page.keyboard.down("w")
    neutral = dict(forward=False, reverse=False, left=False, right=False, fire=False, stickX=0, stickY=0)
    with socket.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", paused=True, **neutral)):
        page.keyboard.press("Escape")
    with socket.expect_event("framereceived", predicate=lambda frame: is_packet(frame, "state")):
        page.keyboard.up("w")
    expect(arena).to_be_visible()
    expect(pause).to_be_visible()
    check_pause_style(page, online=True)

    pause.locator("#infiniteControlsBtn").click()
    controls = page.locator("#controlsDialog")
    expect(controls).to_be_visible()
    pickup_info = controls.locator("#controlsPickupInfo")
    expect(pickup_info).to_contain_text("Most last 15 seconds")
    expect(pickup_info).to_contain_text("Starman lasts 8 seconds")
    expect(pickup_info).to_contain_text("expire after 30 seconds")
    controls.locator("#showFPS").check()
    expect(page.locator("#infiniteFPSIndicator")).to_have_text(re.compile(r"\d+ FPS · [\d.]+ ms"))
    controls.locator("#showFPS").uncheck()
    expect(page.locator("#infiniteFPSIndicator")).to_be_hidden()
    forward = controls.get_by_role("button", name="Rebind player 1 Forward")
    forward.click()
    page.keyboard.press("e")
    expect(forward).to_have_text("E")
    page.keyboard.press("Escape")
    expect(controls).to_be_hidden()
    expect(pause).to_be_visible()

    with socket.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", paused=False, **neutral)):
        resume.click()
    expect(pause).to_be_hidden()
    expect(canvas).to_be_focused()
    with socket.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", paused=False, forward=True)):
        page.keyboard.down("e")
    page.keyboard.up("e")
    page.keyboard.press("Escape")
    expect(pause).to_be_visible()
    with socket.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", paused=False, **neutral)):
        page.keyboard.press("Escape")
    expect(pause).to_be_hidden()
    expect(canvas).to_be_focused()
    with socket.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", paused=True, **neutral)):
        page.keyboard.press("p")
    expect(pause).to_be_visible()


def check_touch_controls(context, page):
    stick = page.locator("#infiniteStick")
    knob = page.locator("#infiniteKnob")
    fire = page.locator("#infiniteFire")
    expect(page.locator("html")).to_have_class(re.compile(r"\bmatch-active\b"))
    assert page.evaluate("""() => {
        const pinch = new Event('gesturechange', {bubbles:true, cancelable:true});
        document.dispatchEvent(pinch);
        return pinch.defaultPrevented;
    }""")
    page.evaluate("""() => {
        Element.prototype.setPointerCapture = () => { throw new DOMException('Pointer expired', 'NotFoundError'); };
    }""")
    expect(stick).to_be_visible()
    expect(fire).to_be_visible()
    cdp = context.new_cdp_session(page)

    def press_both():
        stick_box, fire_box = stick.bounding_box(), fire.bounding_box()
        points = [
            {"x": stick_box["x"] + .7 * stick_box["width"], "y": stick_box["y"] + .5 * stick_box["height"], "id": 11},
            {"x": fire_box["x"] + .5 * fire_box["width"], "y": fire_box["y"] + .5 * fire_box["height"], "id": 12},
        ]
        cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": points})
        expect(fire).to_have_class(re.compile(r"\bheld\b"))
        assert knob.evaluate("element => element.style.getPropertyValue('--stick-x')") not in ("", "0px")

    def expect_released():
        expect(fire).not_to_have_class(re.compile(r"\bheld\b"))
        assert knob.evaluate("element => element.style.getPropertyValue('--stick-x')") == ""

    portrait = page.viewport_size
    press_both()
    page.set_viewport_size({"width": portrait["height"], "height": portrait["width"]})
    page.wait_for_function("() => leqra.getState().touchLandscape")
    expect_released()
    cdp.send("Input.dispatchTouchEvent", {"type": "touchCancel", "touchPoints": []})
    press_both()
    cdp.send("Input.dispatchTouchEvent", {"type": "touchCancel", "touchPoints": []})
    expect_released()
    page.set_viewport_size(portrait)
    page.wait_for_function("() => !leqra.getState().touchLandscape")


def check_public(browser, url, errors):
    with browser.new_context() as first, browser.new_context() as second:
        host = load(first, url, "PUBLIC HOST", errors)
        guest = load(second, url, "PUBLIC GUEST", errors)
        for page in (host, guest):
            expect(page.locator("#infinityToggle")).to_be_checked()
            expect(page.get_by_role("button", name=re.compile(r"^play$", re.IGNORECASE))).to_have_count(1)
        with host.expect_websocket(predicate=lambda ws: ws.url.endswith("/ws/infinite")) as connection:
            host.locator("#startRoomBtn").click()
        expect_pilots(host, 1)
        expect(host.locator("#infiniteLeaderboardTitle")).to_have_text("Top 10 Tanks")
        guest.locator("#startRoomBtn").click()
        for page in (host, guest):
            expect_pilots(page, 2)
            expect_score_rank(page)
            expect(page.locator("#infiniteLeaderboardTitle")).to_have_text("Top 10 Tanks")
            leaders = standings(page)
            expect(leaders).to_contain_text("PUBLIC HOST")
            expect(leaders).to_contain_text("PUBLIC GUEST")
            assert leaders.locator("li").count() <= 10
        check_online_pause(host, connection.value)
        expect_pilots(guest, 2)
        host.locator("#infiniteExit").click()
        expect(host.locator("#infiniteArena")).to_be_hidden()
        expect(host.locator("#startRoomBtn")).to_be_focused()
        expect_pilots(guest, 1)
        expect(guest.locator("#infiniteLeaderboardTitle")).to_have_text("Top 10 Tanks")
        host.locator("#infinityToggleLabel").click()
        expect(host.locator("#infinityToggle")).not_to_be_checked()
        host.locator("#startRoomBtn").click()
        host.wait_for_function("() => ['countdown','playing'].includes(leqra.getState().phase)")
        expect(host.locator("#infiniteArena")).to_be_hidden()
        host.keyboard.press("Escape")
        expect(host.locator("#onlineMenuScreen")).to_be_visible()
        assert host.evaluate("leqra.getState().phase") == "paused"
        host.keyboard.press("Escape")
        expect(host.locator("#onlineMenuScreen")).to_be_hidden()
    print("PASS public Infinity pause, control rebinding, remote standings, and classic Escape", flush=True)


def check_offline(browser, errors):
    index = Path(__file__).resolve().parents[1] / "web" / "index.html"
    with browser.new_context(viewport={"width": 320, "height": 568}, is_mobile=True, has_touch=True) as context:
        page = load(context, index.as_uri(), "OFFLINE PILOT", errors)
        expect(page.locator("#infinityToggle")).to_be_disabled()
        select_room_infinity(page)
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteArena")).to_be_visible()
        expect(page.locator("#infiniteStatus")).to_contain_text(re.compile(r"\b[1-7] bots\b"))
        expect_score_rank(page)
        panel = page.locator("#infiniteLeaderboardPanel")
        panel.locator("summary").tap()
        expect(panel.locator("#infiniteLeaderboard")).to_contain_text("OFFLINE PILOT (you)")
        expect(panel.locator("#infiniteLeaderboard")).to_contain_text("RUST")
        check_touch_controls(context, page)
        page.locator("#pauseBtn").tap()
        check_pause_style(page, online=False)
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
        expect(page.locator("html")).not_to_have_class(re.compile(r"\bmatch-active\b"))
        expect(page.locator('[data-room-mode="infinity"]')).to_have_attribute("aria-checked", "true")
    print("PASS offline file launch, mobile controls, roster bots, and standings", flush=True)


def check_audio(browser, errors):
    index = Path(__file__).resolve().parents[1] / "web" / "index.html"
    with browser.new_context() as context:
        context.add_init_script("""
            window.oscillatorStarts = 0;
            const start = OscillatorNode.prototype.start;
            OscillatorNode.prototype.start = function (...args) {
                window.oscillatorStarts++;
                return start.apply(this, args);
            };
        """)
        page = load(context, index.as_uri(), "SOUND PILOT", errors)
        select_room_infinity(page)
        page.locator("#startRoomBtn").click()
        expect(page.locator("#infiniteStatus")).to_contain_text("Weapons live")
        initial = page.evaluate("oscillatorStarts")
        page.keyboard.press("q")
        page.wait_for_function("(initial) => oscillatorStarts > initial", arg=initial)

        sound = page.locator("#soundBtn")
        sound.click()
        expect(sound).to_have_attribute("aria-label", "Unmute sound")
        muted = page.evaluate("oscillatorStarts")
        page.locator("#infiniteCanvas").focus()
        page.keyboard.down("q")
        page.wait_for_timeout(400)
        page.keyboard.up("q")
        assert page.evaluate("oscillatorStarts") == muted
        page.locator("#pauseBtn").click()
        page.locator("#infiniteExit").click()
        expect(page.locator("#soundBtn")).to_have_attribute("aria-label", "Unmute sound")
    print("PASS Infinity uses the shared firing audio and mute setting", flush=True)


def check_pause_sidebar(browser, url, errors):
    for width, height, touch in ((1560, 900, False), (1280, 900, False), (1000, 800, False), (390, 844, True), (320, 568, True), (568, 320, True)):
        with browser.new_context(viewport={"width": width, "height": height}, is_mobile=touch, has_touch=touch) as context:
            context.add_init_script("localStorage.setItem('leqra.sidebarHidden','1')")
            page = load(context, url, "SIDEBAR PILOT", errors)
            select_room_infinity(page)
            page.locator("#roomPlayers > summary").click()
            page.locator("#addLocalBtn").click()
            player_count = page.evaluate("leqra.getState().room.players.length")
            page.locator("#startRoomBtn").click()
            expect(page.locator("#infiniteArena")).to_be_visible()
            # A queued close event from the mobile dialog must preserve the new owner.
            page.evaluate("""() => {
                const sidebar = document.querySelector('#gameSidebar');
                document.querySelector('#sidebarDetails').append(sidebar);
                const dialog = document.querySelector('#sidebarDialog');
                dialog.showModal(); dialog.close();
                document.querySelector('#pauseBtn').click();
            }""")
            sidebar = page.locator("#infinitePauseSidebar #gameSidebar")
            expect(sidebar).to_be_visible()
            expect(sidebar.locator("#infiniteLeaderboardPanel")).to_have_attribute("open", "")
            expect(sidebar.locator("#infiniteLeaderboard li")).to_have_count(player_count)
            expect(page.locator("#infiniteLeaderboardPanel")).to_have_count(1)
            expect(sidebar.locator("#manualContent")).to_contain_text("Player 2")
            expect(sidebar.locator("#manualContent .warning")).to_contain_text("INFINITY")
            expect(sidebar.locator(".power-row")).to_have_count(10)
            layout = page.locator("#infinitePauseMenu").evaluate("""menu => {
                const box = node => {const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width};};
                return {sidebar:box(menu.querySelector('#infinitePauseSidebar')),card:box(menu.querySelector('.screen-card')),layout:box(menu.querySelector('.infinite-pause-layout'))};
            }""")
            if not touch:
                expected_width = 239 if width <= 1150 else 266
                assert abs(layout["sidebar"]["right"] - (width - 14)) <= 1, layout
                assert abs(layout["sidebar"]["width"] - expected_width) <= 1, layout
                gap = 15 if width <= 1150 else 20
                card_center = (layout["card"]["left"] + layout["card"]["right"]) / 2
                arena_center = (layout["layout"]["left"] + layout["sidebar"]["left"] - gap) / 2
                assert abs(card_center - arena_center) <= 1, layout
            else:
                assert layout["sidebar"]["top"] >= layout["card"]["bottom"], layout
            note = sidebar.locator(".power-note")
            note.scroll_into_view_if_needed()
            expect(note).to_be_in_viewport()
            expect(note).to_contain_text("Starman lasts 8 seconds")
            assert page.locator("#infinitePauseMenu").evaluate("node => node.scrollWidth <= node.clientWidth + 1")

            page.locator("#infiniteControlsBtn").click()
            page.get_by_role("button", name="Rebind player 2 Fire", exact=True).click()
            page.keyboard.press("u")
            page.locator("#openIntroTour").click()
            expect(page.locator("#introTourDialog")).to_be_visible()
            page.locator("#introTourSkip").click()
            page.keyboard.press("Escape")
            expect(page.locator("#controlsDialog")).to_be_hidden()
            expect(page.locator("#infiniteControlsBtn")).to_be_focused()
            expect(sidebar.locator("#manualContent")).to_contain_text("U / ENTER")
            expect(sidebar.locator("#manualContent .warning")).to_contain_text("INFINITY")
            page.locator("#infiniteResumeBtn").click()
            expect(page.locator(".main-grid > #gameSidebar")).to_have_count(1)
            expect(page.locator(".infinite-stage > #infiniteLeaderboardPanel")).to_have_count(1)
            assert not page.locator("#infiniteLeaderboardPanel").evaluate("node => node.open")
            expect(page.locator("#infiniteCanvas")).to_be_focused()
            page.locator("#pauseBtn").click()
            page.locator("#infiniteExit").click()
            expect(page.locator(".main-grid > #gameSidebar")).to_have_count(1)
            expect(page.locator(".infinite-stage > #infiniteLeaderboardPanel")).to_have_count(1)
            expect(page.locator("#gameSidebar .power-note")).to_contain_text("Most timed power-ups last 10 seconds")
            if touch:
                page.locator("#sidebarDetailsBtn").click()
                expect(page.locator("#sidebarDetails > #gameSidebar")).to_be_visible()
                page.locator("#sidebarCloseBtn").click()
                expect(page.locator(".main-grid > #gameSidebar")).to_have_count(1)
    print("PASS shared Infinity pause sidebar, nested tour, bindings, scrolling, and DOM restoration", flush=True)


def check_private(browser, url, errors):
    with browser.new_context() as first, browser.new_context() as second, browser.new_context() as public:
        first.add_init_script("localStorage.setItem('leqra.local2Name', 'ROOM WING')")
        for context in (first, second):
            context.add_init_script("""
                window.gameSockets = [];
                window.WebSocket = class extends WebSocket {
                    constructor(...args) {
                        super(...args);
                        gameSockets.push(this);
                    }
                };
            """)
        host = load(first, url, "ROOM HOST", errors)
        select_room_infinity(host)
        host.locator("#roomTeamMode").select_option("teams")
        host.locator("#roomRulesBtn").click()
        host.locator("#rule-infinityTarget").fill("999")
        host.locator("#rule-teamName1").fill("Orcas")
        host.locator("#applyRulesBtn").click()
        expect(host.locator("#rulesDialog")).to_be_hidden()
        host.locator("#roomPlayers > summary").click()
        host.locator("#addLocalBtn").click()
        expect(host.locator("#roomRoster")).to_contain_text("ROOM WING")
        host.locator("#copyInviteBtn").click()
        host.wait_for_function("() => !!leqra.getState().online?.connected")
        expect(host.locator("#copySpectateBtn")).to_be_hidden()
        expect(host.locator("#copyWatchInGameBtn")).to_have_attribute("hidden", "")
        expect(host.locator("#roomRoleHelp")).to_contain_text("lobby-only")
        room_code = host.evaluate("leqra.getState().online.code")
        guest = load(second, url + "?room=" + quote(room_code, safe=""), "ROOM GUEST", errors)
        guest.locator("#pilotName").fill("ROOM GUEST")
        guest.locator("#joinRoomBtn").click()
        guest.wait_for_function("() => !!leqra.getState().online?.connected")
        expect(host.locator("#startRoomBtn")).to_be_disabled()
        guest.locator("#readyBtn").click()
        expect(host.locator("#startRoomBtn")).to_be_enabled()
        host_frames = []
        guest_frames = []

        def record_infinity(page, frames):
            def listen(socket):
                if socket.url.endswith("/ws/infinite"):
                    socket.on("framereceived", lambda frame: frames.append(frame))
            page.on("websocket", listen)

        record_infinity(host, host_frames)
        record_infinity(guest, guest_frames)
        with host.expect_websocket(predicate=lambda socket: socket.url.endswith("/ws/infinite")) as socket:
            host.locator("#startRoomBtn").click()
        for page in (host, guest):
            expect_pilots(page, 3)
            expect(page.locator("#infiniteStatus")).to_contain_text("First to 999")
            leaders = standings(page)
            expect(leaders).to_contain_text("ROOM HOST")
            expect(leaders).to_contain_text("ROOM GUEST")
            expect(leaders).to_contain_text("ROOM WING")
            expect(page.locator("#infiniteTeamScores")).to_contain_text("Orcas")
        expect(host.locator("#infiniteLocalLoadout")).to_be_visible()
        expect(guest.locator("#infiniteLocalLoadout")).to_be_hidden()
        expect_score_rank(host, split=True)
        expect_score_rank(guest)
        for close_with_escape in (True, False):
            host.locator("#chatBtn").click()
            expect(host.locator("#infiniteArena > #chatPanel")).to_be_visible()
            expect(host.locator("#chatInput")).to_be_focused()
            host.locator("#chatInput").fill("Draft stays in this test room")
            if close_with_escape:
                host.keyboard.press("Escape")
            else:
                host.locator("#chatCloseBtn").click()
            expect(host.locator("#chatPanel")).to_be_hidden()
            expect(host.locator("#infiniteCanvas")).to_be_focused()
            with socket.value.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", forward=True)):
                host.keyboard.down("w")
            host.keyboard.up("w")
        welcome = next(json.loads(frame) for frame in host_frames if is_packet(frame, "welcome"))
        guest_welcome = next(json.loads(frame) for frame in guest_frames if is_packet(frame, "welcome"))
        assert welcome["id"] != welcome["localId"]
        host.locator("#infiniteCanvas").focus()
        with socket.value.expect_event("framesent", predicate=lambda frame: is_packet(frame, "input", local=True, forward=True)):
            host.keyboard.down("ArrowUp")
        with socket.value.expect_event("framereceived", predicate=lambda frame: is_packet(frame, "state") and
                                       any(pilot["id"] == welcome["localId"] and pilot.get("ack", 0) > 0
                                           for pilot in json.loads(frame)["tanks"])):
            host.keyboard.up("ArrowUp")

        def drop(page, paths):
            closed = page.evaluate("""paths => gameSockets.filter(socket => {
                if (socket.readyState !== WebSocket.OPEN || !paths.includes(new URL(socket.url).pathname)) return false;
                socket.close();
                return true;
            }).length""", paths)
            assert closed == len(paths), (closed, paths)

        for paths in (["/ws/infinite"], ["/ws", "/ws/infinite"], None):
            before = len(host_frames)
            with host.expect_websocket(predicate=lambda socket: socket.url.endswith("/ws/infinite")):
                if paths is None:
                    host.reload()
                else:
                    drop(host, paths)
            expect_pilots(host, 3)
            resumed = next(json.loads(frame) for frame in host_frames[before:]
                           if is_packet(frame, "welcome"))
            assert resumed.get("resumed") is True, resumed
            assert all(resumed[key] == welcome[key] for key in ("id", "localId", "seed", "generation")), resumed
            expect(host.locator("#infiniteLocalLoadout")).to_be_visible()

        # Kicking just the local seat should reopen the same arena for P1.
        moderator = host if host.evaluate(
            "() => leqra.getState().online.id === leqra.getState().room.host"
        ) else guest
        before = len(host_frames)
        with host.expect_websocket(predicate=lambda socket: socket.url.endswith("/ws/infinite")):
            moderator.evaluate("""() => {
                const seat = leqra.getState().room.players.find(player => player.kind === 'local');
                const room = gameSockets.find(socket => socket.readyState === WebSocket.OPEN &&
                    new URL(socket.url).pathname === '/ws');
                room.send(JSON.stringify({type:'kick', target:seat.id, member:seat.member}));
            }""")
        expect_pilots(host, 2)
        resumed = next(json.loads(frame) for frame in host_frames[before:] if is_packet(frame, "welcome"))
        assert resumed.get("resumed") is True and "localId" not in resumed, resumed
        assert all(resumed[key] == welcome[key] for key in ("id", "seed", "generation")), resumed
        expect(host.locator("#infiniteLocalLoadout")).to_be_hidden()

        outsider = load(public, url, "PUBLIC SOLO", errors)
        outsider.locator("#startRoomBtn").click()
        expect_pilots(outsider, 1)
        expect(outsider.locator("#infiniteStatus")).not_to_contain_text("First to")
        leaders = standings(outsider)
        expect(leaders).to_contain_text("PUBLIC SOLO")
        expect(leaders).not_to_contain_text("ROOM HOST")

        guest.locator("#pauseBtn").click()
        guest.locator("#infiniteExit").click()
        expect(guest.locator("#infiniteArena")).to_be_hidden()
        expect_pilots(host, 1)
        with guest.expect_websocket(predicate=lambda socket: socket.url.endswith("/ws")):
            drop(guest, ["/ws"])
        guest.wait_for_function("() => !!leqra.getState().online?.connected")
        expect(guest.locator("#infiniteArena")).to_be_hidden()
        # A room transport disconnect can promote the remaining member to host.
        before = len(guest_frames)
        guest.locator("#readyBtn:visible, #startRoomBtn:visible").click()
        expect_pilots(guest, 2)
        rejoined = next(json.loads(frame) for frame in guest_frames[before:] if is_packet(frame, "welcome"))
        assert rejoined["id"] != guest_welcome["id"] and not rejoined.get("resumed"), rejoined
        moderator, other = ((host, guest) if host.evaluate(
            "() => leqra.getState().online.id === leqra.getState().room.host"
        ) else (guest, host))
        other.locator("#pauseBtn").click()
        other.locator("#infiniteControlsBtn").click()
        expect(other.locator("#controlsDialog")).to_be_visible()
        other.locator("#openIntroTour").click()
        expect(other.locator("#introTourDialog")).to_be_visible()
        moderator.locator("#pauseBtn").click()
        moderator.locator("#infiniteExit").click()
        moderator.locator("#endInfinityBtn").click()
        moderator.locator("#actionConfirmAccept").click()
        expect(other.locator("#infiniteArena")).to_be_hidden()
        expect(other.locator("#infinitePauseMenu")).to_be_hidden()
        expect(other.locator("#controlsDialog")).to_be_hidden()
        expect(other.locator("#introTourDialog")).to_be_hidden()
        expect(other.locator(".main-grid > #gameSidebar")).to_have_count(1)
        expect(other.locator("#readyBtn")).to_contain_text("READY")
        expect(moderator.locator("#endInfinityBtn")).to_be_hidden()
        assert all(page.evaluate("leqra.getState().online.connected") for page in (host, guest))
        expect_pilots(outsider, 1)
    print("PASS private teams, P2 input and removal, automatic reconnect and reload, public isolation, exit and end", flush=True)


def check_rank_outside_leaders(browser, url, errors, screenshot_dir=None):
    with browser.new_context() as context:
        context.add_init_script("""
            localStorage.setItem('leqra.local2Name', 'RANKED P2');
            window.WebSocket = class extends WebSocket {
                constructor(...args) {
                    super(...args);
                    if (!window.captureRankGame || new URL(args[0],location.href).pathname !== '/ws/infinite') return;
                    window.rankGameSocket = this;
                    this.addEventListener('message', event => {
                        const packet = JSON.parse(event.data);
                        if (packet.type === 'welcome') this.rankWelcome = packet;
                        if (packet.type === 'state') this.rankState = packet;
                    });
                }
            };
        """)
        page = load(context, url, "RANKED PILOT", errors)
        page.locator("#roomPlayers > summary").click()
        page.locator("#addLocalBtn").click()
        expect(page.locator("#roomRoster")).to_contain_text("RANKED P2")
        page.evaluate("""async () => {
            const url = new URL('/ws/infinite', location.href);
            url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
            window.rankPeers = [];
            await Promise.all(Array.from({length:12}, (_, index) => new Promise((resolve, reject) => {
                const socket = new WebSocket(url);
                rankPeers.push(socket);
                const timer = setTimeout(() => reject(Error('Rank fixture pilot did not join')), 5000);
                socket.onopen = () => socket.send(JSON.stringify({type:'join',version:leqra.version,name:'RANK PEER '+index}));
                socket.onerror = () => {clearTimeout(timer);reject(Error('Rank fixture connection failed'));};
                socket.onmessage = event => {
                    const packet = JSON.parse(event.data);
                    if (packet.type === 'welcome') {clearTimeout(timer);resolve();}
                    else if (packet.type === 'error') {clearTimeout(timer);reject(Error(packet.message));}
                };
            })));
            window.captureRankGame = true;
        }""")
        page.locator("#startRoomBtn").click()
        expect_pilots(page, 14)
        expect_score_rank(page, split=True)
        leaders = standings(page)
        expect(page.locator("#infiniteLeaderboardTitle")).to_have_text("Top 10 Tanks")
        expect(leaders.locator("li")).to_have_count(12)
        page.evaluate("window.rankBoard = document.querySelector('#infiniteLeaderboard')")
        matches_authority = """() => {
            const socket=window.rankGameSocket, state=socket?.rankState, welcome=socket?.rankWelcome;
            if (!state || !welcome || welcome.localId == null) return false;
            const ids=[welcome.id,welcome.localId], locals=ids.map(id=>state.tanks.find(tank=>tank.id===id));
            if (locals.some(tank=>!tank || !Number.isSafeInteger(tank.rank) || tank.rank<=10)) return false;
            const top=state.leaderboard.slice(0,10);
            if (top.length!==10 || new Set(top.map(tank=>tank.id)).size!==10 || top.some(tank=>ids.includes(tank.id))) return false;
            const canonical=color=>{const node=document.createElement('span');node.style.color=color;return node.style.color;};
            const expected=[...top.map((tank,i)=>({tank,rank:i+1,local:0})),
                ...locals.map((tank,i)=>({tank,rank:tank.rank,local:i+1})).sort((a,b)=>a.rank-b.rank)];
            const rows=[...document.querySelectorAll('#infiniteLeaderboard > li')];
            return rows.length===12 && expected.every(({tank,rank,local},i)=>{
                const row=rows[i], label=tank.name+(local===1?' (you)':local===2?' (P2)':'');
                return row.value===rank && row.querySelector('span')?.textContent===label &&
                    row.querySelector('strong')?.textContent===String(tank.score) &&
                    (row.dataset.local||'')===(local?'p'+local:'') &&
                    row.classList.contains('off-board-local')===!!local &&
                    getComputedStyle(row).color===canonical(leqraInfinityArt.colors[tank.colorIndex]) &&
                    (!local || row.style.getPropertyValue('--local-highlight')===['#bf5cff','#ff4fd8'][local-1]);
            }) && rows.filter(row=>row.dataset.local==='p1').length===1 && rows.filter(row=>row.dataset.local==='p2').length===1;
        }"""
        page.wait_for_function(matches_authority)
        if screenshot_dir is not None:
            page.screenshot(path=str(screenshot_dir / f"{browser.browser_type.name}-rank-active.png"))
        page.locator("#pauseBtn").click()
        pause = page.locator("#infinitePauseMenu")
        expect(pause).to_be_visible()
        expect(pause.locator("#infinitePauseSidebar #infiniteLeaderboard > li")).to_have_count(12)
        assert page.evaluate("document.querySelector('#infiniteLeaderboard') === rankBoard")
        expect(page.locator("#infiniteLeaderboardPanel")).to_have_count(1)
        page.wait_for_function(matches_authority)
        if screenshot_dir is not None:
            page.screenshot(path=str(screenshot_dir / f"{browser.browser_type.name}-rank-paused.png"))
        pause.locator("#infiniteResumeBtn").click()
        expect(pause).to_be_hidden()
        expect(page.locator(".infinite-stage #infiniteLeaderboard > li")).to_have_count(12)
        assert page.evaluate("document.querySelector('#infiniteLeaderboard') === rankBoard")
        page.wait_for_function(matches_authority)
        page.locator("#pauseBtn").click()
        page.locator("#infiniteExit").click()
        page.evaluate("rankPeers.forEach(socket => socket.close())")
    print("PASS top ten plus both local ranks, scores, and colors stay correct in active and paused Infinity", flush=True)


def check_mobile_ranks(browser, url, errors):
    for width in (320, 390):
        with browser.new_context(viewport={"width": width, "height": 844}, is_mobile=True, has_touch=True) as context:
            page = load(context, url, "RANK PILOT", errors)
            page.locator("#startRoomBtn").tap()
            expect_pilots(page, 1)
            expect_score_rank(page)
            expect(page.locator("#infiniteLeaderboardTitle")).to_have_text("Top 10 Tanks")
            for split in (False, True):
                if split:
                    page.locator("#pauseBtn").tap()
                    page.locator("#infiniteExit").tap()
                    select_room_infinity(page)
                    page.locator("#roomPlayers > summary").tap()
                    page.locator("#addLocalBtn").tap()
                    page.locator("#copyInviteBtn").tap()
                    page.wait_for_function("() => !!leqra.getState().online?.connected")
                    page.locator("#startRoomBtn").tap()
                    expect_pilots(page, 2)
                    expect_score_rank(page, split=True)
                    expect(page.locator("#infiniteLeaderboardTitle")).to_have_text("Scoreboard")
                    colors = page.evaluate("""() => {
                        const canonical=color=>{const node=document.createElement('span');node.style.color=color;return node.style.color;};
                        return {actual:[...document.querySelectorAll('#infiniteKills .infinite-personal-score')].map(node=>getComputedStyle(node).color),expected:leqraInfinityArt.colors.slice(0,2).map(canonical)};
                    }""")
                    assert colors["actual"] == colors["expected"], colors
                layout = page.locator("#infiniteArena .infinite-statusbar").evaluate("""header => {
                    const box = node => {const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom};};
                    return {header:box(header),title:box(header.querySelector('.arena-title')),items:[...header.querySelectorAll('.bar-right > *')].filter(node=>node.getClientRects().length).map(box),width:innerWidth,overflow:header.scrollWidth>header.clientWidth};
                }""")
                assert not layout["overflow"] and layout["header"]["right"] <= width + 1, layout
                assert layout["title"]["right"] <= layout["items"][0]["left"] + 1, layout
                for previous, current in zip(layout["items"], layout["items"][1:]):
                    assert previous["right"] <= current["left"] + 1, layout
                assert all(0 <= item["left"] < item["right"] <= width + 1 for item in layout["items"]), layout
                assert page.locator("#infiniteArena").evaluate("node => node.scrollWidth <= node.clientWidth + 1")
                assert page.locator("#gameHeader").evaluate("node => node.scrollWidth <= node.clientWidth + 1")
    print("PASS solo and private P2 ranks fit 320px and 390px online headers", flush=True)


def check_shared_header(browser, url, errors):
    for width, height, touch in ((1280, 900, False), (390, 844, True), (320, 568, True), (844, 390, True)):
        with browser.new_context(viewport={"width": width, "height": height}, is_mobile=touch, has_touch=touch) as context:
            page = load(context, url, "HEADER PILOT", errors)
            page.locator("#infinityToggleLabel").click()
            page.locator("#startRoomBtn").click()
            page.wait_for_function("() => ['countdown','playing'].includes(leqra.getState().phase)")
            page.evaluate("window.originalGameHeader = document.querySelector('#gameHeader')")
            measure = """() => {
                const header=document.querySelector('#gameHeader'),brand=header.querySelector('.brand'),controls=header.querySelector('.header-right');
                const box=node=>{const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height};};
                return {header:box(header),brand:box(brand),controls:box(controls),font:getComputedStyle(header.querySelector('.brand-name')).font,overflow:header.scrollWidth>header.clientWidth};
            }"""
            fixed = page.evaluate(measure)
            page.locator("#pauseBtn").click()
            page.locator("#returnRoomBtn").click()
            if page.locator("#actionConfirmAccept").is_visible():
                page.locator("#actionConfirmAccept").click()
            page.wait_for_function("() => leqra.getState().phase === 'menu'")
            select_room_infinity(page)
            page.locator("#startRoomBtn").click()
            expect(page.locator("#infiniteHeader > #gameHeader")).to_be_visible()
            expect(page.locator("#infiniteArena > #chatPanel")).to_be_hidden()
            assert page.evaluate("document.querySelector('#gameHeader') === originalGameHeader")
            infinite = page.evaluate(measure)
            assert fixed == infinite, (fixed, infinite)
            assert not infinite["overflow"] and infinite["header"]["right"] <= width + 1, infinite
            version = page.evaluate("leqra.version")
            expect(page.locator("#gameHeader .github-link #headerVersion")).to_have_text("v" + version)
            expect(page.locator("#gameHeader .github-link")).to_have_attribute("href", "https://github.com/nhooyr/leqra")
            expect(page.locator("#gameHeader")).to_have_count(1)
            expect(page.locator("#pauseBtn")).to_be_visible()
            page.locator("#roomBtn").click()
            expect(page.locator("#infinitePauseMenu")).to_be_visible()
            page.locator("#infiniteResumeBtn").click()
            page.locator("#pauseBtn").click()
            page.locator("#infiniteExit").click()
            expect(page.locator(".app > #gameHeader")).to_be_visible()
            expect(page.locator("body > #chatPanel")).to_be_hidden()
            assert page.evaluate("document.querySelector('#gameHeader') === originalGameHeader")
    print("PASS shared header identity, geometry, source version, controls, and restoration", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default=os.environ.get("LEQRA_URL", "http://localhost:8080"))
    args = parser.parse_args()
    url = args.url.rstrip("/") + "/"
    errors = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(chromium_sandbox=True)
        try:
            check_public(browser, url, errors)
            check_offline(browser, errors)
            check_audio(browser, errors)
            check_pause_sidebar(browser, url, errors)
            check_private(browser, url, errors)
            check_rank_outside_leaders(browser, url, errors)
            check_mobile_ranks(browser, url, errors)
            check_shared_header(browser, url, errors)
        finally:
            browser.close()
    assert not errors, errors
