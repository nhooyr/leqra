"""Check small-screen layouts against a running leqra server.

Run with Playwright Chromium installed and a dedicated server running.
python3 src/tests/mobile_layout_browser.py http://localhost:8080
"""

import argparse
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


def mobile_context(browser, devices, width, height):
    return browser.new_context(
        viewport={"width": width, "height": height}, has_touch=True, is_mobile=True,
        user_agent=devices["iPhone SE"]["user_agent"],
    )


def open_page(context, url, errors):
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("localStorage.setItem('leqra.introTour.v1', '1')")
    page.goto(url)
    page.wait_for_function("() => !!window.leqra")
    return page


def check_landscape(browser, devices, errors, has_safe_area_override):
    index = Path(__file__).resolve().parents[1] / "web" / "index.html"
    with mobile_context(browser, devices, 568, 320) as context:
        page = open_page(context, index.as_uri(), errors)
        if has_safe_area_override:
            cdp = context.new_cdp_session(page)
            cdp.send("Emulation.setSafeAreaInsetsOverride", {
                "insets": {"top": 8, "right": 48, "bottom": 21, "left": 48}
            })
        page.locator("#roomSettings > summary").tap()
        page.locator('[data-room-mode="ctf"]').tap()
        page.locator("#roomRulesBtn").tap()
        rules = page.locator("#rulesDialog")
        expect(rules).to_be_visible()
        if has_safe_area_override:
            bounds = rules.bounding_box()
            assert bounds["x"] >= 48 and bounds["x"] + bounds["width"] <= 520, bounds
        rules.locator("[data-close-dialog]").tap()
        fixed_pause_size = page.locator("#pauseBtn").evaluate("""button => {
            const style = getComputedStyle(button);
            return {width: parseFloat(style.width), height: parseFloat(style.height)};
        }""")
        page.locator('[data-room-mode="infinity"]').tap()
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteArena")).to_be_visible()
        expect(page.locator("#infiniteHeader > #gameHeader")).to_be_visible()
        page.locator("#infiniteLeaderboardPanel > summary").tap()
        layout = page.evaluate("""() => {
            const panel = document.querySelector('#infiniteLeaderboardPanel');
            const summary = panel.querySelector('summary');
            const list = panel.querySelector('#infiniteLeaderboard');
            list.replaceChildren(...Array.from({length: 10}, () => {
                const row = document.createElement('li');
                const name = document.createElement('span');
                const score = document.createElement('strong');
                name.textContent = 'LLLLLLLLLLLLLLLL';
                score.textContent = '-1000';
                row.append(name, score);
                return row;
            }));
            panel.scrollTop = panel.scrollHeight;
            const fire = document.querySelector('#infiniteFire');
            const hit = element => {
                const r = element.getBoundingClientRect();
                return element.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2));
            };
            const brand = document.querySelector('#gameHeader .brand').getBoundingClientRect();
            const actions = document.querySelector('#gameHeader .header-right').getBoundingClientRect();
            return {
                fireReachable: hit(fire), summaryReachable: hit(summary), scrollTop: panel.scrollTop,
                top: Math.min(brand.top, actions.top), left: brand.left, right: actions.right
            };
        }""")
        assert layout["fireReachable"] and layout["summaryReachable"] and layout["scrollTop"] > 0, layout
        if has_safe_area_override:
            assert layout["top"] >= 8 and layout["left"] >= 48 and layout["right"] <= 520, layout
        page.locator("#infiniteLeaderboardPanel > summary").tap()
        expect(page.locator("#infiniteLeaderboardPanel")).not_to_have_attribute("open", "")
        pause_button = page.locator("#pauseBtn")
        trigger = pause_button.bounding_box()
        assert trigger["width"] >= 30 and trigger["height"] >= 30, trigger
        assert abs(trigger["width"] - fixed_pause_size["width"]) <= 1, (trigger, fixed_pause_size)
        assert abs(trigger["height"] - fixed_pause_size["height"]) <= 1, (trigger, fixed_pause_size)
        pause_button.tap()
        pause = page.locator("#infinitePauseMenu")
        expect(pause).to_be_visible()
        expect(pause.get_by_text("The battle is paused. Your tank is safe.")).to_be_visible()
        for name in ("BACK TO THE BATTLE", "Controls", "Exit Infinity"):
            button = pause.get_by_role("button", name=name, exact=True)
            expect(button).to_be_in_viewport(ratio=1)
            assert button.bounding_box()["height"] >= 44, name
        if has_safe_area_override:
            bounds = pause.locator(".screen-card").bounding_box()
            assert bounds["x"] >= 48 and bounds["x"] + bounds["width"] <= 520, bounds
            assert bounds["y"] >= 8 and bounds["y"] + bounds["height"] <= 299, bounds
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
        expect(page.locator(".app > #gameHeader")).to_be_visible()
    print("PASS landscape rules, notch clearance, and Infinity leaderboard and pause layouts", flush=True)


def check_split_infinity(browser, devices, errors):
    index = Path(__file__).resolve().parents[1] / "web" / "index.html"
    with mobile_context(browser, devices, 280, 520) as context:
        page = open_page(context, index.as_uri(), errors)
        page.evaluate("leqraInfinity.start('offline', {localName: 'Wingmate'})")
        for width, height, split in ((280, 520, "stacked"), (568, 320, "side")):
            page.set_viewport_size({"width": width, "height": height})
            expect(page.locator("#infiniteArena")).to_have_attribute("data-split", split)
            divider = page.evaluate("""split => {
                const canvas = document.getElementById('infiniteCanvas'), c = canvas.getContext('2d');
                const width = canvas.clientWidth, height = canvas.clientHeight;
                const vertical = split === 'side';
                const x = Math.ceil(width / 2), y = Math.ceil(height / 2);
                const pixel = (px, py) => Array.from(c.getImageData(
                    Math.floor(px * canvas.width / width), Math.floor(py * canvas.height / height), 1, 1
                ).data).slice(0, 3);
                const rgb = color => color.slice(1).match(/../g).map(pair => parseInt(pair, 16));
                const {accent, arena} = leqraInfinityArt.theme;
                return [pixel(x, y), pixel(x + (vertical ? 3 : 0), y + (vertical ? 0 : 3)), rgb(accent), rgb(arena)];
            }""", split)
            assert divider[:2] == divider[2:], divider
            boxes = page.evaluate("""() => {
                document.querySelectorAll('#infiniteKills .infinite-personal-score').forEach((score, i) => {
                    score.textContent = `P${i+1} -999 (#99)`;
                });
                return Object.fromEntries(['gameHeader','infiniteKills','infiniteCanvas','infiniteFire','infiniteStick','pauseBtn','infiniteLocalLoadout'].map(id => {
                    const {left,top,right,bottom} = document.getElementById(id).getBoundingClientRect();
                    return [id,[left,top,right,bottom]];
                }));
            }""")
            for left, top, right, bottom in boxes.values():
                assert 0 <= left < right <= width + 1 and 0 <= top < bottom <= height + 1, boxes
            left, top, right, bottom = boxes["pauseBtn"]
            assert right - left >= 30 and bottom - top >= 30, boxes
            left, top, right, bottom = boxes["infiniteCanvas"]
            for control in ("infiniteFire", "infiniteStick"):
                if split == "stacked":
                    assert boxes[control][3] <= (top + bottom) / 2 + 1, boxes
                else:
                    assert boxes[control][2] <= (left + right) / 2 + 1, boxes
    print("PASS Player 2 divider, long scores, and primary touch controls", flush=True)


def check_narrow_online(browser, devices, url, errors):
    with mobile_context(browser, devices, 280, 480) as context:
        page = open_page(context, url, errors)
        page.locator("#infinityToggleLabel").tap()
        page.locator("#copyInviteBtn").tap()
        page.wait_for_function("() => leqra.getState().online?.connected")
        page.locator("#startRoomBtn").tap()
        page.wait_for_function("() => leqra.getState().phase === 'playing'")
        links = page.evaluate("""() => {
            const bounds = selector => {
                const {left, top, right, bottom} = document.querySelector(selector).getBoundingClientRect();
                return {left, top, right, bottom};
            };
            return {github: bounds('.github-link'), room: bounds('#roomBtn'),
                header: bounds('#gameHeader'), viewportWidth: innerWidth};
        }""")
        github, room = links["github"], links["room"]
        assert (github["right"] <= room["left"] or room["right"] <= github["left"] or
                github["bottom"] <= room["top"] or room["bottom"] <= github["top"]), links
        for rect in (github, room, links["header"]):
            assert 0 <= rect["left"] < rect["right"] <= links["viewportWidth"] + 1, links
        page.locator("#chatBtn").tap()
        positions = page.evaluate("""() => {
            const viewport = window.visualViewport;
            // Simulate the short visual viewport left above a soft keyboard.
            Object.defineProperties(viewport, {
                height: {value: 140, configurable: true},
                offsetTop: {value: 35, configurable: true}
            });
            viewport.dispatchEvent(new Event('resize'));
            const bounds = id => {
                const {top, bottom} = document.getElementById(id).getBoundingClientRect();
                return {top, bottom};
            };
            return {panel: bounds('chatPanel'), close: bounds('chatCloseBtn'), input: bounds('chatInput')};
        }""")
        assert all(35 <= rect["top"] <= rect["bottom"] <= 175 for rect in positions.values()), positions
        page.locator("#chatCloseBtn").tap()
        expect(page.locator("#chatPanel")).to_be_hidden()
    print("PASS narrow online header and chat with a short keyboard viewport", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://localhost:8080")
    parser.add_argument("--engine", choices=("chromium", "webkit"), default="chromium")
    args = parser.parse_args()
    with sync_playwright() as playwright:
        if args.engine == "chromium":
            browser = playwright.chromium.launch(chromium_sandbox=True)
        else:
            browser = playwright.webkit.launch()
        errors = []
        try:
            check_landscape(browser, playwright.devices, errors, args.engine == "chromium")
            check_split_infinity(browser, playwright.devices, errors)
            check_narrow_online(browser, playwright.devices, args.url, errors)
            assert not errors, errors
        finally:
            browser.close()
