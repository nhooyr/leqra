"""Exercise real same-version PWA upgrades against disposable HTTP fixtures.

Install Playwright plus the requested browsers, then run this from the repo root:
    python3 src/tests/pwa_update_browser.py --browser chromium --browser webkit
Artifacts are optional and must be written outside the repository.
"""

import argparse
from hashlib import sha256
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
from pathlib import Path
import re
import threading
from time import monotonic
from urllib.parse import urlsplit
from urllib.request import urlopen

from playwright.sync_api import expect, sync_playwright


WEB = Path(__file__).resolve().parents[1] / "web"
SHELL_FILES = (
    "theme.js", "theme.css", "style.css", "favicon.svg", "netcode.js", "game.js",
    "infinite-maze.js", "infinite.js", "pwa.js", "manifest.webmanifest", "sw.js",
)
ICON_FILES = (
    "apple-touch-icon-512.png", "apple-touch-icon.png", "favicon-256.png",
    "icon-1024.png", "icon-192.png", "icon-512.png", "icon-maskable-1024.png", "icon-maskable-512.png",
)


class Release:
    def __init__(self, stale_header=False):
        self.files = {"index.html": (WEB / "index.html").read_bytes()}
        self.version = re.search(rb'src="assets/(v\d+\.\d+\.\d+)/game\.js"', self.files["index.html"]).group(1).decode()
        self.base = "assets/" + self.version + "/"
        for name in SHELL_FILES + ICON_FILES:
            self.files[self.base + name] = (WEB / self.base / name).read_bytes()
        if stale_header:
            self.files[self.base + "style.css"] += b"\n#gameHeader{transform:translateY(-20px)!important}\n"
        # Match appBuildID's path/length separators, order and 64-bit hash prefix.
        digest = sha256()
        for path in ("index.html",) + tuple(self.base + name for name in SHELL_FILES + ICON_FILES):
            data = self.files[path]
            digest.update(("web/" + path + "\0" + str(len(data)) + "\0").encode())
            digest.update(data)
        self.build = self.version + "-" + digest.hexdigest()[:16]
        html = self.files["index.html"].decode()
        html = re.sub(r'(\s(?:src|href)=")(assets/[^"]+)', lambda match: match[1] + match[2] + "?build=" + self.build, html)
        self.html = html.replace("</head>", '<meta name="leqra-build" content="' + self.build + '">\n</head>', 1).encode()
        self.worker = ("'use strict';\nself.LEQRA_BUILD = '" + self.build + "';\n").encode() + self.files[self.base + "sw.js"]


class Fixture:
    def __init__(self):
        self.old, self.new = Release(stale_header=True), Release()
        assert self.old.build != self.new.build
        self.release = self.old
        self.requests = []
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                path = urlsplit(self.path).path
                release = fixture.release
                fixture.requests.append((self.path, release.build))
                headers = {"X-Leqra-Build": release.build}
                if path == "/api/build":
                    body = json.dumps({"version": release.version[1:], "build": release.build}).encode()
                    mime, cache = "application/json", "no-store"
                elif path == "/sw.js" or re.fullmatch(r"/assets/v\d+\.\d+\.\d+/sw\.js", path):
                    body, mime, cache = release.worker, "text/javascript", "no-store"
                    headers["Service-Worker-Allowed"] = "/"
                elif path in ("/", "/index.html"):
                    body, mime, cache = release.html, "text/html", "no-cache, must-revalidate"
                    headers["ETag"] = '"' + release.build + '"'
                elif path == "/legacy-registration.html":
                    body = b"<script>navigator.serviceWorker.register('/assets/v0.0.1/sw.js',{scope:'/'});</script>"
                    mime, cache = "text/html", "no-store"
                elif path[1:] in release.files:
                    body = release.files[path[1:]]
                    mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
                    cache = "public, max-age=31536000, immutable"
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Cache-Control", cache)
                self.send_header("Content-Length", str(len(body)))
                for key, value in headers.items():
                    self.send_header(key, value)
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = "http://127.0.0.1:" + str(self.server.server_port)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


INIT = """(() => {
    sessionStorage.setItem('pwaLoads', String(Number(sessionStorage.getItem('pwaLoads') || 0) + 1));
    window.pwaDocument = crypto.randomUUID();
    if (!localStorage.getItem('pwaFixtureSeeded')) {
        localStorage.setItem('leqra.name', 'UPDATE P1');
        localStorage.setItem('leqra.local2Name', 'UPDATE P2');
        localStorage.setItem('leqra.introTour.v1', '1');
        localStorage.setItem('pwaFixtureSeeded', '1');
    }
})();"""

PROBE = """async () => {
    const worker = navigator.serviceWorker.controller;
    if (!worker) return null;
    return await new Promise((resolve, reject) => {
        const channel = new MessageChannel();
        const timeout = setTimeout(() => reject(Error('worker build probe timed out')), 3000);
        channel.port1.onmessage = event => {
            clearTimeout(timeout); channel.port1.close(); channel.port2.close(); resolve(event.data);
        };
        worker.postMessage({type:'LEQRA_BUILD_INFO'}, [channel.port2]);
    });
}"""


def wait_for_worker(page, build):
    page.wait_for_function("!!navigator.serviceWorker.controller", timeout=30000)
    deadline = monotonic() + 30
    while monotonic() < deadline:
        info = page.evaluate(PROBE)
        if info and info.get("build") == build:
            return
        page.wait_for_timeout(100)
    raise AssertionError("controller did not activate build " + build)


def setup_state(page):
    return page.evaluate("""() => ({
        roster: __test.localRoom.players.map(({id,kind,name,team,colorIndex,difficulty}) => ({kind,name,team,color:__test.teamColor(id,team,colorIndex),difficulty})),
        rules: __test.currentRules()
    })""")


def check_coherence(page, release):
    assert page.locator('meta[name="leqra-build"]').get_attribute("content") == release.build
    assert page.evaluate("leqra.version") == release.version[1:]
    assert page.evaluate("getComputedStyle(document.getElementById('gameHeader')).transform") == "none"
    refs = page.locator('[src^="assets/"], [href^="assets/"]').evaluate_all("nodes => nodes.map(node => node.getAttribute('src') || node.getAttribute('href'))")
    assert refs and all(ref.startswith(release.base) and ref.endswith("?build=" + release.build) for ref in refs), refs
    assert page.evaluate(PROBE)["build"] == release.build


def check_same_version_upgrade(browser, screenshots):
    errors = []
    with Fixture() as fixture, browser.new_context(viewport={"width": 1440, "height": 1000}, service_workers="allow") as context:
        context.add_init_script(INIT)
        page = context.new_page()
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(fixture.url + "/?test")
        page.wait_for_function("() => !!window.__test && !!window.leqra")
        wait_for_worker(page, fixture.old.build)
        assert page.evaluate("getComputedStyle(document.getElementById('gameHeader')).transform") == "matrix(1, 0, 0, 1, 0, -20)"
        assert page.evaluate("Number(sessionStorage.pwaLoads)") == 1, 'the initial controller claim reloaded the page'

        # Use the actual room controls to leave public Infinity, add P2 and save paint.
        page.locator("#infinityToggle").uncheck()
        page.locator("#roomPlayers > summary").click()
        page.locator("#addLocalBtn").click()
        page.locator('#roomRoster [data-tank-color="0"]').select_option("5")
        p2 = page.evaluate("__test.localRoom.players.find(p => p.kind === 'local').id")
        page.locator(f'#roomRoster [data-tank-color="{p2}"]').select_option("7")
        page.locator("#roomSettings > summary").click()
        page.locator('[data-room-mode="koth"]').click()
        page.locator("#roomMapSize").select_option("huge")
        page.locator("#startRoomBtn").focus()
        expected = setup_state(page)
        document_id = page.evaluate("pwaDocument")
        page.locator("#startRoomBtn").click()
        page.wait_for_function("leqra.getState().phase === 'playing'")
        assert not page.evaluate("leqra.prepareUpdate()")

        fixture.release = fixture.new
        page.evaluate("""() => {
            document.dispatchEvent(new Event('visibilitychange'));
            window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted:true}));
        }""")
        wait_for_worker(page, fixture.new.build)
        # The new worker is active and cached, but the running document stays on A.
        page.wait_for_timeout(1400)
        assert page.evaluate("pwaDocument") == document_id
        assert page.evaluate("Number(sessionStorage.pwaLoads)") == 1
        assert page.locator('meta[name="leqra-build"]').get_attribute("content") == fixture.old.build
        assert page.evaluate("leqra.getState().phase") in ("playing", "roundOver", "countdown")
        keys = page.evaluate("caches.keys()")
        assert "leqra-app-" + fixture.new.build in keys, keys
        if screenshots:
            page.screenshot(path=str(screenshots / (browser.browser_type.name + "-pwa-busy-old-header.png")))

        # Returning to the room enables the production save-before-reload hook.
        with page.expect_navigation(wait_until="load", timeout=15000):
            page.evaluate("__test.returnToRoom()")
        page.wait_for_function("() => !!window.__test && !!window.leqra")
        wait_for_worker(page, fixture.new.build)
        assert page.evaluate("Number(sessionStorage.pwaLoads)") == 2
        assert page.evaluate("pwaDocument") != document_id
        check_coherence(page, fixture.new)
        assert setup_state(page) == expected, {"expected": expected, "actual": setup_state(page)}
        page.wait_for_timeout(1400)
        assert page.evaluate("Number(sessionStorage.pwaLoads)") == 2, 'the update reloaded more than once'
        if screenshots:
            page.screenshot(path=str(screenshots / (browser.browser_type.name + "-pwa-updated-header.png")))

        # Disable the actual network and reload the completed build B cache.
        context.set_offline(True)
        page.reload(wait_until="load")
        page.wait_for_function("() => !!window.__test && !!window.leqra")
        check_coherence(page, fixture.new)
        assert setup_state(page) == expected, {"expected": expected, "actual": setup_state(page)}
        assert page.evaluate("Number(sessionStorage.pwaLoads)") == 3
        assert not errors, errors
        context.set_offline(False)
        print("PASS", browser.browser_type.name, "same-version upgrade, busy deferral, one safe reload, paint/roster persistence and offline build coherence", flush=True)


def check_legacy_alias(browser):
    with Fixture() as fixture, browser.new_context(service_workers="allow") as context:
        context.add_init_script(INIT)
        page = context.new_page()
        page.goto(fixture.url + "/legacy-registration.html")
        wait_for_worker(page, fixture.old.build)
        assert page.evaluate("navigator.serviceWorker.controller.scriptURL").endswith("/assets/v0.0.1/sw.js")
        fixture.release = fixture.new
        page.evaluate("async () => (await navigator.serviceWorker.ready).update()")
        wait_for_worker(page, fixture.new.build)
        # Legacy documents lack a safe reload protocol; migration occurs on fresh navigation.
        page.goto(fixture.url + "/?test")
        page.wait_for_function("() => !!window.leqra")
        page.wait_for_function("navigator.serviceWorker.controller?.scriptURL.endsWith('/sw.js') && !navigator.serviceWorker.controller.scriptURL.includes('/assets/')")
        check_coherence(page, fixture.new)
        print("PASS", browser.browser_type.name, "legacy worker alias updates and migrates to stable registration on fresh navigation", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", action="append", choices=("chromium", "webkit"), help="defaults to Chromium")
    parser.add_argument("--screenshots", type=Path, help="optional existing directory outside the repository")
    parser.add_argument("--server", help="optional compiled Go server URL whose build fingerprint must match the fixture")
    args = parser.parse_args()
    if args.server:
        with urlopen(args.server.rstrip("/") + "/api/build", timeout=10) as response:
            info = json.load(response)
        assert info["build"] == Release().build, ("fixture and compiled server fingerprints differ", info)
    if args.screenshots:
        args.screenshots = args.screenshots.resolve()
        assert args.screenshots.is_dir(), "screenshot directory must already exist"
        assert not args.screenshots.is_relative_to(WEB.parents[1]), "generated screenshots must stay outside the repository"
    with sync_playwright() as playwright:
        for name in args.browser or ["chromium"]:
            browser = getattr(playwright, name).launch(headless=True)
            try:
                check_same_version_upgrade(browser, args.screenshots)
                check_legacy_alias(browser)
            finally:
                browser.close()


if __name__ == "__main__":
    main()
