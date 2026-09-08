# leqra v4.41.0 — current verification

See **TEST-NOTES-v4.41.0.md** for current commands, results and limitations. Current raw logs are in `tests/results/v4.41.0/`. Historical browser fixtures below were not rerun for this release.

## Historical v4.23 verification

Historical release verification is documented in **TEST-NOTES-v4.23.md**. v4.23 adds focused coverage for versioned/PWA assets and cache headers, the online version handshake, graceful shutdown notification/client return-to-Home behavior, no startup WebSocket, Unshare maze preservation, balanced Teams activation, chat-focus input routing, and the restored Leave match action.

Representative commands from the extracted source tree:

```sh
go test -race -count=1 ./...
go vet ./...
go build -trimpath -o /tmp/leqra-v4.23 .
node --check web/theme.js
node --check web/netcode.js
node --check web/game.js
node --test tests/*.test.cjs
python3 tests/polish423_sigterm.py
```

For the focused real-WebSocket browser fixture in environments that cannot navigate Chromium to loopback URLs:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790   go test -run '^TestBrowserFixture$' -timeout 30m
python3 tests/polish423_browser.py --server http://127.0.0.1:18790   --output tests/results/v4.23-polish
```

Retained regression suites used by the release include:

```sh
python3 tests/polish422_browser.py
python3 tests/polish418_browser.py --output tests/results/v4.23-retained
```

The build sandbox can inject the exact shipped HTML/CSS/JavaScript into Chromium and can use real loopback WebSockets, but direct Chromium navigation to `http://127.0.0.1/...` and `file:` was administratively blocked during this release run. Therefore the service-worker/manifest/static-cache contract is verified at the Go handler/source level rather than claiming a native install prompt was exercised here. Physical iPhone/iPad Safari and Android Chrome remain the final install/add-to-home-screen acceptance targets.
