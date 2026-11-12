"""Check the 10px UI font floor and wrapping in Chromium and WebKit.

Run with Playwright installed: python3 src/tests/typography_browser.py [server URL]
Without a URL this checks the current source directly, including offline Infinity.
"""
import argparse
from pathlib import Path
from playwright.sync_api import expect, sync_playwright


def check_text(page):
    small = page.evaluate("""() => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), bad = [];
        for (let node; node = walker.nextNode();) {
            if (!node.textContent.trim()) continue;
            const parent = node.parentElement;
            if (!parent || !parent.getClientRects().length) continue;
            const style = getComputedStyle(parent);
            if (style.visibility === 'hidden' || style.display === 'none') continue;
            const size = parseFloat(style.fontSize);
            if (size < 9.99) bad.push({text: node.textContent.slice(0, 60), size, id: parent.id});
        }
        return bad;
    }""")
    assert not small, small
    assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), "Horizontal page overflow"
    for dialog in page.locator("dialog[open]").all():
        assert dialog.evaluate("node => node.scrollWidth <= node.clientWidth"), dialog.get_attribute("id")
    names = page.locator(".loadout-name:visible, .control-pilot:visible")
    assert names.evaluate_all("nodes => nodes.every(node => node.scrollWidth <= node.clientWidth && node.scrollHeight <= node.clientHeight)"), names.all_text_contents()


def check_context(browser, url, width, height, touch):
    with browser.new_context(viewport={"width": width, "height": height}, is_mobile=touch,
                             has_touch=touch, service_workers="block") as context:
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.add_init_script("localStorage.setItem('leqra.introTour.v1', '1')")
        page.goto(url)
        page.wait_for_function("() => !!window.leqraInfinity")
        toggle = page.locator("#infinityToggle")
        if toggle.is_enabled() and toggle.is_checked():
            toggle.uncheck()
        for paired in (False, True):
            if paired:
                page.locator("#roomPlayers").evaluate("node => node.open = true")
                page.locator("#addLocalBtn").click()
            check_text(page)
            page.locator("#roomControlsBtn").click()
            check_text(page)
            page.locator("#showFPS").check()
            page.locator('[data-close-dialog="controlsDialog"]').click()
            page.locator("#roomSettings").evaluate("node => node.open = true")
            page.locator('[data-room-mode="elimination"]').click()
            page.locator("#roomRulesBtn").click()
            check_text(page)
            page.locator('[data-close-dialog="rulesDialog"]').click()
            page.locator("#startRoomBtn").click()
            page.wait_for_function("() => leqra.getState().phase === 'playing'")
            check_text(page)
            page.locator("#pauseBtn").click()
            expect(page.locator("#onlineMenuScreen")).to_be_visible()
            check_text(page)
            page.locator("#returnRoomBtn").click()
            page.locator("#roomSettings").evaluate("node => node.open = true")
            page.locator('[data-room-mode="infinity"]').click()
            page.locator("#startRoomBtn").click()
            expect(page.locator("#infiniteArena")).to_be_visible()
            check_text(page)
            page.locator("#pauseBtn").click()
            check_text(page)
            page.locator("#infiniteControlsBtn").click()
            check_text(page)
            page.locator("#openIntroTour").click()
            for _ in range(3):
                check_text(page)
                page.locator("#introTourNext").click()
            page.locator('[data-close-dialog="controlsDialog"]').click()
            page.locator("#infiniteExit").click()
            print(f"PASS {browser.browser_type.name} {width}x{height} {'two pilots' if paired else 'solo'}: font floor, controls, rules, fixed/Infinity HUD, pause and tour", flush=True)
        assert not errors, errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default=(Path(__file__).resolve().parents[1] / "web/index.html").as_uri() + "?test=1")
    parser.add_argument("--browser", action="append", choices=("chromium", "webkit"))
    args = parser.parse_args()
    with sync_playwright() as playwright:
        for engine in args.browser or ("chromium", "webkit"):
            browser = getattr(playwright, engine).launch()
            try:
                for width, height, touch in ((1280, 900, False), (390, 844, True),
                                            (320, 568, True), (844, 390, True)):
                    check_context(browser, args.url, width, height, touch)
            finally:
                browser.close()
