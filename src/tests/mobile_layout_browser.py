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
        page.locator('[data-room-mode="infinity"]').tap()
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteArena")).to_be_visible()
        page.locator("#infiniteLeaderboardPanel > summary").tap()
        layout = page.evaluate("""() => {
            const panel = document.querySelector('#infiniteLeaderboardPanel');
            const summary = panel.querySelector('summary');
            const list = panel.querySelector('ol');
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
            const header = getComputedStyle(document.querySelector('.infinite-header'));
            return {
                fireReachable: hit(fire), summaryReachable: hit(summary), scrollTop: panel.scrollTop,
                top: parseFloat(header.paddingTop), left: parseFloat(header.paddingLeft),
                right: parseFloat(header.paddingRight)
            };
        }""")
        assert layout["fireReachable"] and layout["summaryReachable"] and layout["scrollTop"] > 0, layout
        if has_safe_area_override:
            assert layout["top"] >= 8 and layout["left"] >= 48 and layout["right"] >= 48, layout
        page.locator("#infiniteLeaderboardPanel > summary").tap()
        expect(page.locator("#infiniteLeaderboardPanel")).not_to_have_attribute("open", "")
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
    print("PASS landscape rules, notch clearance, and expanded Infinity leaderboard", flush=True)


def check_narrow_online(browser, devices, url, errors):
    with mobile_context(browser, devices, 280, 480) as context:
        page = open_page(context, url, errors)
        page.locator("#infinityToggleLabel").tap()
        page.locator("#copyInviteBtn").tap()
        page.wait_for_function("() => leqra.getState().online?.connected")
        page.locator("#startRoomBtn").tap()
        page.wait_for_function("() => leqra.getState().phase === 'playing'")
        links = page.evaluate("""() => ({
            github: document.querySelector('.github-link').getBoundingClientRect().right,
            room: document.querySelector('#roomBtn').getBoundingClientRect().left
        })""")
        assert links["github"] <= links["room"], links
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
            check_narrow_online(browser, playwright.devices, args.url, errors)
            assert not errors, errors
        finally:
            browser.close()
