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
        guest.locator("#startRoomBtn").click()
        for page in (host, guest):
            expect_pilots(page, 2)
            expect(page.locator("#infiniteKills")).to_have_text("Score 0")
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
        expect(page.locator("#infiniteKills")).to_have_text("Score 0")
        panel = page.locator("#infiniteLeaderboardPanel")
        panel.locator("summary").tap()
        expect(panel.locator("#infiniteLeaderboard")).to_contain_text("OFFLINE PILOT (you)")
        expect(panel.locator("#infiniteLeaderboard")).to_contain_text("Bot ")
        check_touch_controls(context, page)
        page.locator("#infinitePauseBtn").tap()
        check_pause_style(page, online=False)
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
        expect(page.locator("html")).not_to_have_class(re.compile(r"\bmatch-active\b"))
        expect(page.locator('[data-room-mode="infinity"]')).to_have_attribute("aria-checked", "true")
    print("PASS offline file launch, mobile controls, random bots, and standings", flush=True)


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

        sound = page.locator("#infiniteSoundBtn")
        sound.click()
        expect(sound).to_have_attribute("aria-label", "Unmute sound")
        muted = page.evaluate("oscillatorStarts")
        page.locator("#infiniteCanvas").focus()
        page.keyboard.down("q")
        page.wait_for_timeout(400)
        page.keyboard.up("q")
        assert page.evaluate("oscillatorStarts") == muted
        page.locator("#infinitePauseBtn").click()
        page.locator("#infiniteExit").click()
        expect(page.locator("#soundBtn")).to_have_attribute("aria-label", "Unmute sound")
    print("PASS Infinity uses the shared firing audio and mute setting", flush=True)


def check_private(browser, url, errors):
    with browser.new_context() as first, browser.new_context() as second, browser.new_context() as public:
        host = load(first, url, "ROOM HOST", errors)
        select_room_infinity(host)
        host.locator("#copyInviteBtn").click()
        host.wait_for_function("() => !!leqra.getState().online?.connected")
        room_code = host.evaluate("leqra.getState().online.code")
        guest = load(second, url + "?room=" + quote(room_code, safe=""), "ROOM GUEST", errors)
        guest.locator("#pilotName").fill("ROOM GUEST")
        guest.locator("#joinRoomBtn").click()
        guest.wait_for_function("() => !!leqra.getState().online?.connected")
        expect(host.locator("#startRoomBtn")).to_be_disabled()
        guest.locator("#readyBtn").click()
        expect(host.locator("#startRoomBtn")).to_be_enabled()
        host.locator("#startRoomBtn").click()
        for page in (host, guest):
            expect_pilots(page, 2)
            leaders = standings(page)
            expect(leaders).to_contain_text("ROOM HOST")
            expect(leaders).to_contain_text("ROOM GUEST")

        outsider = load(public, url, "PUBLIC SOLO", errors)
        outsider.locator("#startRoomBtn").click()
        expect_pilots(outsider, 1)
        leaders = standings(outsider)
        expect(leaders).to_contain_text("PUBLIC SOLO")
        expect(leaders).not_to_contain_text("ROOM HOST")

        guest.locator("#infinitePauseBtn").click()
        guest.locator("#infiniteExit").click()
        expect(guest.locator("#infiniteArena")).to_be_hidden()
        expect_pilots(host, 1)
        expect(guest.locator("#readyBtn")).to_have_accessible_name("JOIN INFINITY")
        guest.locator("#readyBtn").click()
        expect_pilots(guest, 2)
        guest.locator("#infinitePauseBtn").click()
        guest.locator("#infiniteControlsBtn").click()
        expect(guest.locator("#controlsDialog")).to_be_visible()
        host.locator("#infinitePauseBtn").click()
        host.locator("#infiniteExit").click()
        host.locator("#endInfinityBtn").click()
        host.locator("#actionConfirmAccept").click()
        expect(guest.locator("#infiniteArena")).to_be_hidden()
        expect(guest.locator("#infinitePauseMenu")).to_be_hidden()
        expect(guest.locator("#controlsDialog")).to_be_hidden()
        expect(guest.locator("#readyBtn")).to_contain_text("READY")
        expect(host.locator("#endInfinityBtn")).to_be_hidden()
        assert all(page.evaluate("leqra.getState().online.connected") for page in (host, guest))
        expect_pilots(outsider, 1)
    print("PASS invited room, ready, private standings, re-entry, and end", flush=True)


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
            check_private(browser, url, errors)
        finally:
            browser.close()
    assert not errors, errors
