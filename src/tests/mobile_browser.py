"""Run mobile integration checks on a dedicated local leqra server.

Usage: python3 src/tests/mobile_browser.py [URL] [--engine chromium|webkit]
"""

import argparse
import json
import re
from urllib.parse import quote

from playwright.sync_api import expect, sync_playwright


def load(context, url, name, errors):
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script(f"localStorage.setItem('leqra.name', {json.dumps(name)})")
    page.goto(url)
    page.wait_for_function("() => window.leqra && window.leqraInfinity")
    assert page.evaluate("leqra.getState().touchUI")
    tour = page.locator("#introTourDialog")
    if tour.is_visible():
        page.locator("#introTourSkip").tap()
        expect(tour).to_be_hidden()
    return page


def choose_mode(page, mode):
    settings = page.locator("#roomSettings")
    if settings.get_attribute("open") is None:
        settings.locator("summary").tap()
    choice = settings.locator(f'[data-room-mode="{mode}"]')
    choice.tap()
    expect(choice).to_have_attribute("aria-checked", "true")
    settings.locator("summary").tap()


def require_on_screen(page, *selectors):
    viewport = page.evaluate("""() => ({
        width: visualViewport.width, height: visualViewport.height,
        x: visualViewport.offsetLeft, y: visualViewport.offsetTop
    })""")
    for selector in selectors:
        box = page.locator(selector).bounding_box()
        assert box and box["width"] >= 40 and box["height"] >= 40, (selector, box)
        assert box["x"] >= viewport["x"] - 1, (selector, box, viewport)
        assert box["y"] >= viewport["y"] - 1, (selector, box, viewport)
        assert box["x"] + box["width"] <= viewport["x"] + viewport["width"] + 1, (selector, box, viewport)
        assert box["y"] + box["height"] <= viewport["y"] + viewport["height"] + 1, (selector, box, viewport)


def play_offline(browser, device, url, errors):
    with browser.new_context(**device) as context:
        page = load(context, url + "?test=1", "MOBILE LOCAL", errors)
        page.wait_for_function("() => !!navigator.serviceWorker.controller")
        context.set_offline(True)
        page.reload()
        page.wait_for_function("() => !!window.leqraInfinity")

        for mode in ("elimination", "ctf", "koth", "survival"):
            choose_mode(page, mode)
            page.locator("#startRoomBtn").tap()
            page.wait_for_function("() => leqra.getState().phase === 'playing'")
            assert page.evaluate("leqra.getState().rules.mode") == mode
            require_on_screen(page, "#arena", "#stickZone", "#fireBtn")
            if mode == "elimination":
                page.locator("#fireBtn").tap()
                page.wait_for_function("() => __test.bullets.some(b => b.owner === 0)")
                page.set_viewport_size({"width": 568, "height": 320})
                page.wait_for_function("() => leqra.getState().touchLandscape")
                require_on_screen(page, "#arena", "#stickZone", "#fireBtn")
                page.set_viewport_size(device["viewport"])
                page.wait_for_function("() => !leqra.getState().touchLandscape")
            page.reload()
            page.wait_for_function("() => !!window.leqra")

        choose_mode(page, "infinity")
        page.locator("#startRoomBtn").tap()
        arena = page.locator("#infiniteArena")
        expect(arena).to_have_attribute("data-mode", "offline")
        expect(page.locator("#infiniteStatus")).to_contain_text(re.compile(r"\b[1-7] bots\b"))
        require_on_screen(page, "#infiniteCanvas", "#infiniteStick", "#infiniteFire", "#infinitePauseBtn")
        page.set_viewport_size({"width": 568, "height": 320})
        page.wait_for_function("() => leqra.getState().touchLandscape")
        require_on_screen(page, "#infiniteCanvas", "#infiniteStick", "#infiniteFire", "#infinitePauseBtn")
        page.locator("#infiniteLeaderboardPanel summary").tap()
        expect(page.locator("#infiniteLeaderboard")).to_contain_text("MOBILE LOCAL (you)")
        page.locator("#infinitePauseBtn").tap()
        pause = page.locator("#infinitePauseMenu")
        expect(pause).to_be_visible()
        require_on_screen(page, "#infiniteResumeBtn", "#infiniteControlsBtn", "#infiniteExit")
        page.locator("#infiniteControlsBtn").tap()
        controls = page.locator("#controlsDialog")
        expect(controls).to_be_visible()
        controls.get_by_role("button", name="Close controls").tap()
        expect(controls).to_be_hidden()
        expect(pause).to_be_visible()
        page.locator("#infiniteResumeBtn").tap()
        expect(pause).to_be_hidden()
        page.locator("#infinitePauseBtn").tap()
        page.locator("#infiniteExit").tap()
        expect(arena).to_be_hidden()
    print("PASS installed offline app, all five modes, touch Fire, and landscape pause controls", flush=True)


def play_shared_room(browser, device, url, errors):
    with browser.new_context(**device) as first, browser.new_context(**device) as second:
        host = load(first, url + "?test=1", "MOBILE HOST", errors)
        choose_mode(host, "elimination")
        host.locator("#copyInviteBtn").tap()
        host.wait_for_function("() => !!leqra.getState().online?.connected")
        room = host.evaluate("leqra.getState().online.code")
        guest = load(second, url + "?test=1&room=" + quote(room, safe=""), "MOBILE GUEST", errors)
        guest.locator("#pilotName").fill("MOBILE GUEST")
        guest.locator("#joinRoomBtn").tap()
        guest.wait_for_function("() => !!leqra.getState().online?.connected")
        expect(host.locator("#startRoomBtn")).to_be_disabled()
        guest.locator("#readyBtn").tap()
        expect(host.locator("#startRoomBtn")).to_be_enabled()
        host.locator("#startRoomBtn").tap()
        for page in (host, guest):
            page.wait_for_function("() => leqra.getState().phase === 'playing'")
            require_on_screen(page, "#arena", "#stickZone", "#fireBtn")
        guest.locator("#fireBtn").tap()
        guest.wait_for_function("""() => {
            const self = __test.online.id;
            return __test.online.snapshots.at(-1)?.tankMap.get(self)?.shotSerial > 0;
        }""")
        seat = guest.evaluate("__test.online.id")
        guest.evaluate("() => { window.testSocket = __test.online.socket; testSocket.close(4000, 'test reconnect'); }")
        guest.wait_for_function("""() => leqra.getState().online?.connected &&
            __test.online.socket !== window.testSocket && leqra.getState().phase === 'playing'""")
        assert guest.evaluate("__test.online.id") == seat
    print("PASS two touch clients ready, fire on the server, and resume the same seat", flush=True)


def play_public_infinity(browser, device, url, errors):
    with browser.new_context(**device) as context:
        page = load(context, url, "MOBILE PUBLIC", errors)
        expect(page.locator("#infinityToggle")).to_be_checked()
        messages = []
        page.on("websocket", lambda socket: socket.on("framesent", lambda frame: messages.append(frame)))
        upgrades = []
        if browser.browser_type.name == "chromium":
            session = context.new_cdp_session(page)
            session.send("Network.enable")
            session.on("Network.webSocketHandshakeResponseReceived", lambda event: upgrades.append(event["response"]["headers"]))
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteStatus")).to_contain_text("1 online")
        if browser.browser_type.name == "chromium":
            assert any("permessage-deflate" in value for headers in upgrades for name, value in headers.items()
                       if name.lower() == "sec-websocket-extensions"), upgrades
        require_on_screen(page, "#infiniteCanvas", "#infiniteStick", "#infiniteFire")
        page.locator("#infiniteFire").tap()
        assert any(isinstance(frame, str) and json.loads(frame).get("fire") is True for frame in messages), messages
        page.locator("#infiniteSoundBtn").tap()
        expect(page.locator("#infiniteSoundBtn")).to_have_attribute("aria-label", "Unmute sound")
        page.locator("#infinitePauseBtn").tap()
        expect(page.locator("#infinitePauseMenu")).to_be_visible()
        assert any(isinstance(frame, str) and json.loads(frame).get("paused") is True for frame in messages), messages
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
    print("PASS public Infinity touch Fire, mute, and pause", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://localhost:8080")
    parser.add_argument("--engine", choices=["chromium", "webkit"], default="chromium")
    args = parser.parse_args()
    url = args.url.rstrip("/") + "/"
    errors = []
    with sync_playwright() as playwright:
        if args.engine == "webkit":
            browser = playwright.webkit.launch()
            device = playwright.devices["iPhone 13"]
        else:
            browser = playwright.chromium.launch(chromium_sandbox=True)
            device = playwright.devices["Pixel 7"]
        try:
            play_offline(browser, device, url, errors)
            play_shared_room(browser, device, url, errors)
            play_public_infinity(browser, device, url, errors)
        finally:
            browser.close()
    assert not errors, errors
