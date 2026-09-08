# leqra v4.45.1 — current verification

See [TEST-NOTES-v4.45.1.md](releases/TEST-NOTES-v4.45.1.md) for the release checks and limitations. Archived reports preserve the paths used when they were written; use the commands below for the current repository layout.

## Current commands

Run from the repository root, where `go.mod` lives. Go 1.23 or newer is required for the server; JavaScript tests use the Node.js test runner.

```sh
go test -race -count=1 ./...
go vet ./...
go build -trimpath -o bin/leqra ./src
node --check src/web/theme.js
node --check src/web/netcode.js
node --check src/web/game.js
node --test src/tests/*.test.cjs
python3 -m unittest discover -s tests -p 'test_deploy.py' -v
```

Deployment tests use temporary directories and mock builds, SSH, transfers, and
server commands; they do not contact the deployment host. If Node.js is unavailable,
the JavaScript suite also runs with `deno test --allow-read --allow-env src/tests/*.test.cjs`.

On Windows, build with `go build -trimpath -o bin/leqra.exe ./src`. To target a Go test or opt-in fixture, include the package path, for example `go test -run '^TestBrowserFixture$' ./src`.

## Historical browser and protocol fixtures

Historical release verification is documented in [TEST-NOTES-v4.23.md](releases/TEST-NOTES-v4.23.md). That release added focused coverage for versioned/PWA assets and cache headers, the online version handshake, graceful shutdown notification/client return-to-Home behavior, no startup WebSocket, Unshare maze preservation, balanced Teams activation, chat-focus input routing, and the restored Leave match action.

The scripts below are retained for reference, were not rerun for the current release, and contain version-specific assertions and UI expectations. They need review before use against a newer release. Browser harnesses require Playwright and their configured Chromium executable; protocol harnesses may also require the Python `websockets` package. Invoke them from the repository root:

```sh
python3 src/tests/polish423_sigterm.py
```

For the focused real-WebSocket browser fixture, run the Go fixture in one terminal and the Python script in another:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 \
  go test -run '^TestBrowserFixture$' -timeout 30m ./src
python3 src/tests/polish423_browser.py --server http://127.0.0.1:18790
```

Other retained browser suites:

```sh
python3 src/tests/polish422_browser.py
python3 src/tests/polish418_browser.py --output src/tests/results/v4.23-retained
```

`polish423_browser.py` resolves its default output directory relative to `src/`, producing `src/tests/results/v4.23-polish/`. The explicit `polish418_browser.py` output above is relative to the repository root. Older performance harnesses that accept a `PROJECT_ROOT` argument expect the directory containing `web/`; pass `src`, not `.`.

The current Browser tool explicitly blocked the game page under its URL policy and prohibited alternate capture routes. No browser harness was run for this release. Go handler/source checks of the service worker, manifest and static-cache contract do not establish native layout or install behavior. Physical iPhone/iPad Safari and Android Chrome remain acceptance targets; the retained README screenshot is not current browser evidence.
