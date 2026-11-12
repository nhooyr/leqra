"""Check Infinity Combat Log visibility against a dedicated leqra server.

python3 src/tests/infinity_sidebar_browser.py http://localhost:8080
"""

import argparse
from pathlib import Path
import re

from playwright.sync_api import expect, sync_playwright


def check_sidebar(browser, url, mobile, source_css):
    with browser.new_context(
        viewport={"width": 390 if mobile else 1280, "height": 844},
        has_touch=mobile, is_mobile=mobile, service_workers="block",
    ) as context:
        if source_css:
            index = Path(__file__).resolve().parents[1] / "web" / "index.html"
            asset = re.search(r'href="(assets/v[\d.]+/style.css)"', index.read_text())[1]
            context.route("**/style.css*", lambda route: route.fulfill(
                path=str(index.parent / asset), content_type="text/css"
            ))
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.add_init_script("localStorage.setItem('leqra.introTour.v1', '1')")
        page.goto(url.rstrip("/") + "/?test")
        page.wait_for_function("() => !!window.leqraInfinity && !!window.__test")
        log = page.locator("#combatLog")
        log.evaluate("element => element.textContent = 'Preserved fixed-maze log'")

        def expect_log(hidden):
            expect(page.locator(".log-panel")).to_have_css("display", "none" if hidden else "block")
            expect(log).to_have_text("Preserved fixed-maze log")

        expect(page.locator("body")).to_have_class(re.compile(r"\binfinity-preview\b"))
        expect_log(True)
        # Exercise the shared Sidebar dialog's mount as well as its inline home.
        page.locator("#sidebarDetailsBtn").evaluate("button => button.click()")
        expect(page.locator("#sidebarDialog #gameSidebar")).to_be_visible()
        expect_log(True)
        page.locator("#sidebarCloseBtn").click()

        page.locator("#infinityToggle").uncheck()
        expect_log(False)
        for selected in (True, False):
            page.evaluate("selected => __test.setLocalRules({...__test.currentRules(), infinity: selected})", selected)
            expect_log(selected)

        for mode in ("offline", "online"):
            page.evaluate("mode => leqraInfinity.start(mode, {public: mode === 'online'})", mode)
            expect(page.locator("#infiniteArena")).to_be_visible()
            expect_log(True)
            page.locator("#pauseBtn" if mobile else "#sidebarBtn").click()
            expect(page.locator("#infinitePauseSidebar #gameSidebar")).to_be_visible()
            expect_log(True)
            page.locator("#infiniteResumeBtn").click()
            expect_log(True)
            page.evaluate("() => leqraInfinity.close()")
            expect_log(False)
        assert not errors, errors
    print(f"PASS {'mobile' if mobile else 'desktop'} Infinity preview, Sidebar dialog, pause, and fixed-maze restoration", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://localhost:8080")
    parser.add_argument("--engine", choices=("chromium", "webkit"), default="chromium")
    parser.add_argument("--source-css", action="store_true", help="Use current source CSS before rebuilding embedded assets")
    args = parser.parse_args()
    with sync_playwright() as playwright:
        browser = getattr(playwright, args.engine).launch()
        try:
            for mobile in (False, True):
                check_sidebar(browser, args.url, mobile, args.source_css)
        finally:
            browser.close()
