# Testing leqra

Run from the repository root with Go 1.23+, Node.js, and Python 3.

```sh
go test -race -count=1 ./...
go vet ./...
go build -trimpath -o bin/leqra ./src
node --check src/web/assets/v*/game.js
node --test src/tests/*.test.cjs
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The Python suite exercises local startup and deployment with mocked builds, browser launches, SSH, transfers, and remote commands.

Keep generated reports and screenshots local. Older raw results are available in the repository history.

## Browser checks for the current release

The maintained Playwright harnesses cover the quick tour, room regressions, touch and keyboard controls, and local and online play. The mobile checks use Pixel and iPhone browser profiles in Chromium and WebKit.
Node-based browser harnesses also require the `playwright` package.

```sh
python3 -m pip install playwright
python3 -m playwright install chromium webkit
python3 src/tests/intro_tour_browser.py
```

Use a dedicated local database for online checks so test accounts and scores do
not enter your development data. Start the server in a separate terminal:

```sh
LEQRA_TEST_DIR="$(mktemp -d)"
LEQRA_DATA="$LEQRA_TEST_DIR/data.sqlite" LEQRA_ADMIN_ADDR=off go run ./src
```

Then run the online checks.

```sh
python3 src/tests/infinity_browser.py http://localhost:8080
python3 src/tests/audit_browser.py http://localhost:8080
python3 src/tests/mobile_browser.py http://localhost:8080
python3 src/tests/mobile_browser.py http://localhost:8080 --engine webkit
python3 src/tests/mobile_layout_browser.py http://localhost:8080
python3 src/tests/mobile_layout_browser.py http://localhost:8080 --engine webkit
python3 src/tests/pwa_update_browser.py --browser chromium --browser webkit
python3 src/tests/typography_browser.py http://localhost:8080 --browser chromium --browser webkit
node src/tests/web_room_chat_browser.cjs http://localhost:8080 --disposable /tmp/leqra-room-chat
node src/tests/grenade_hints_browser.cjs /tmp/leqra-touch-controls
LEQRA_BROWSER=webkit node src/tests/grenade_hints_browser.cjs /tmp/leqra-touch-controls-webkit
node src/tests/local_p2_layout_browser.cjs http://localhost:8080
node src/tests/local_p2_input_browser.cjs http://localhost:8080 --disposable
node src/tests/showcase_browser.cjs http://localhost:8080
node src/tests/power_help_browser.cjs http://localhost:8080
```

The PWA harness starts disposable local servers and checks same-version upgrades, legacy worker migration, match deferral, saved room setup, and offline reloads in both engines. Browser emulation does not verify an installed iOS Home Screen app on a physical device.

The typography harness checks the 10px minimum, full callsigns, and overflow in ready rooms, settings, fixed games, Infinity and pause menus, with one and two local pilots at desktop, phone and landscape sizes.

The chat harness sends messages in both directions from lobbies, fixed matches,
and Room Infinity in desktop, mobile, and simulated standalone PWA layouts.
Native iOS and Android apps intentionally omit chat. The touch-control harness
checks that a fully deflected joystick and firing ring stay clear of the loadout
panel, the target is centered, control captions are absent, and instructions
remain in the sidebar/help.

The local P2 harnesses check phone/tablet layouts and touch plus external
keyboard/mouse routing in Chromium and WebKit. P1 keeps touch input while P2
receives both keyboard layouts and mouse input; fixed mazes share the arena and
Infinity has separate camera views. Physical accessories need a device check.

The showcase harness opens **Controls → Showcase** in Chromium and WebKit,
checks the frozen frame and full-screen sizing, and verifies Escape and
background/return exits without changing saved settings. The unit suite also
checks that the web, iOS, and Android scene data match, and that P1's laser leaves
the barrel forward, shows visible reflections, hits one destroyed tank and
clears every survivor. The destroyed tank keeps its callsign; Cannon trails
retain their frozen history. Desktop checks cover the
header, status bar, loadout and expanded leaderboard; the generator captures
this same in-game view.
Mobile checks include the gameplay header, controls and loadout, the denser
portrait scene with four loose pickups, all ten power-ups equipped on living
tanks, and rotation between portrait and landscape.
The power-help harness checks active-map timers and draft room-rule changes,
including Infinity's fixed power-up rules.

For live checks, run `go run ./src` and open the served page in separate browser contexts. Check a shared match and verify that the service worker can reload the app offline after installation.

## Historical harnesses

The other Python browser and protocol scripts in `src/tests/`, including `browser_smoke.py` and `protocol_smoke.py`, are release-specific. Run them against their matching revision. Their assertions can cover retired behavior such as grenade self-damage. For historical scripts that request the opt-in Go fixture, start it from that revision.

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 \
  go test -run '^TestBrowserFixture$' -timeout 30m ./src
```

[Historical verification reports](releases/)
