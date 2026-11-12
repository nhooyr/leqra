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

```sh
python3 -m pip install playwright
python3 -m playwright install chromium webkit
python3 src/tests/intro_tour_browser.py
```

With a dedicated local server running, run the online checks.

```sh
python3 src/tests/infinity_browser.py http://localhost:8080
python3 src/tests/audit_browser.py http://localhost:8080
python3 src/tests/mobile_browser.py http://localhost:8080
python3 src/tests/mobile_browser.py http://localhost:8080 --engine webkit
python3 src/tests/mobile_layout_browser.py http://localhost:8080
python3 src/tests/mobile_layout_browser.py http://localhost:8080 --engine webkit
python3 src/tests/pwa_update_browser.py --browser chromium --browser webkit
```

The PWA harness starts disposable local servers and checks same-version upgrades, legacy worker migration, match deferral, saved room setup, and offline reloads in both engines. Browser emulation does not verify an installed iOS Home Screen app on a physical device.

For live checks, run `go run ./src` and open the served page in separate browser contexts. Check a shared match and verify that the service worker can reload the app offline after installation.

## Historical harnesses

The other Python browser and protocol scripts in `src/tests/`, including `browser_smoke.py` and `protocol_smoke.py`, are release-specific. Run them against their matching revision. Their assertions can cover retired behavior such as grenade self-damage. For historical scripts that request the opt-in Go fixture, start it from that revision.

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 \
  go test -run '^TestBrowserFixture$' -timeout 30m ./src
```

[Historical verification reports](releases/)
