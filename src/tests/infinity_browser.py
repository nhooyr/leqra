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


def check_touch_controls(context, page):
    stick = page.locator("#infiniteStick")
    knob = page.locator("#infiniteKnob")
    fire = page.locator("#infiniteFire")
    expect(stick).to_be_visible()
    expect(fire).to_be_visible()
    stick_box = stick.bounding_box()
    fire_box = fire.bounding_box()
    points = [
        {"x": stick_box["x"] + .7 * stick_box["width"], "y": stick_box["y"] + .5 * stick_box["height"], "id": 11},
        {"x": fire_box["x"] + .5 * fire_box["width"], "y": fire_box["y"] + .5 * fire_box["height"], "id": 12},
    ]
    cdp = context.new_cdp_session(page)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": points})
    expect(fire).to_have_class(re.compile(r"\bheld\b"))
    assert knob.evaluate("element => element.style.getPropertyValue('--stick-x')") not in ("", "0px")
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    expect(fire).not_to_have_class(re.compile(r"\bheld\b"))
    assert knob.evaluate("element => element.style.getPropertyValue('--stick-x')") == ""


def check_public(browser, url, errors):
    with browser.new_context() as first, browser.new_context() as second:
        host = load(first, url, "PUBLIC HOST", errors)
        guest = load(second, url, "PUBLIC GUEST", errors)
        for page in (host, guest):
            expect(page.locator("#infinityToggle")).to_be_checked()
            expect(page.get_by_role("button", name=re.compile(r"^play$", re.IGNORECASE))).to_have_count(1)
            page.locator("#startRoomBtn").click()
        for page in (host, guest):
            expect_pilots(page, 2)
            expect(page.locator("#infiniteKills")).to_have_text("Score 0")
            leaders = standings(page)
            expect(leaders).to_contain_text("PUBLIC HOST")
            expect(leaders).to_contain_text("PUBLIC GUEST")
            assert leaders.locator("li").count() <= 10
        host.keyboard.press("Escape")
        expect(host.locator("#infiniteArena")).to_be_hidden()
        expect(host.locator("#startRoomBtn")).to_be_focused()
        expect_pilots(guest, 1)
        host.locator("#infinityToggleLabel").click()
        expect(host.locator("#infinityToggle")).not_to_be_checked()
        host.locator("#startRoomBtn").click()
        host.wait_for_function("() => ['countdown','playing'].includes(leqra.getState().phase)")
        expect(host.locator("#infiniteArena")).to_be_hidden()
    print("PASS public Infinity default, remote standings, and classic Play when switched off", flush=True)


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
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
        expect(page.locator('[data-room-mode="infinity"]')).to_have_attribute("aria-checked", "true")
    print("PASS offline file launch, mobile controls, random bots, and standings", flush=True)


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

        guest.locator("#infiniteExit").click()
        expect(guest.locator("#infiniteArena")).to_be_hidden()
        expect_pilots(host, 1)
        expect(guest.locator("#readyBtn")).to_have_accessible_name("JOIN INFINITY")
        guest.locator("#readyBtn").click()
        expect_pilots(guest, 2)
        host.locator("#infiniteExit").click()
        host.locator("#endInfinityBtn").click()
        host.locator("#actionConfirmAccept").click()
        expect(guest.locator("#infiniteArena")).to_be_hidden()
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
            check_private(browser, url, errors)
        finally:
            browser.close()
    assert not errors, errors
