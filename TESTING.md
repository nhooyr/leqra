# leqra v4.19 — current verification

Current verification is documented in **TEST-NOTES-v4.19.md**. The final race-enabled Go run records **463 top-level tests passing**, **866 passing test/subtest events**, **2 opt-in skips**, and **0 failures**. The JavaScript suite remains **56/56**. Browser coverage includes **23/23 Safari/WebKit identity-path checks**, **12/12 branding/migration**, **16/16 desktop gameplay/HUD**, **6/6 narrow-mobile**, **9/9 v4.18 presentation/layout**, and **71/71 real-WebSocket matchmaking** checks. Go vet, JavaScript syntax checks, and the compiled Go build also pass.

```sh
go test -race -count=1 -json ./...
go vet ./...
node --check web/theme.js
node --check web/netcode.js
node --check web/game.js
node --test tests/*.test.cjs
python3 tests/safari419_browser.py
python3 tests/branding417_browser.py
python3 tests/polish415_browser.py
python3 tests/polish415_mobile_browser.py
python3 tests/polish418_browser.py

# Real WebSocket matchmaking fixture (run in a separate terminal/process):
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18041 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=0
python3 tests/matchmaking_browser.py http://127.0.0.1:18041 \
  --output tests/results/v4.19-matchmaking

go build -trimpath -o leqra .
```

A native Safari/WebKit runtime is not installed in this build environment. The Safari suite runs the shipped WebKit/iOS detection, CSS, touch, sizing, and fallback paths in system Chromium under Safari/iPhone/iPad identities. It verifies those code paths and catches JavaScript/layout regressions, but it is **not** a native-Safari FPS benchmark. Physical Safari on macOS/iPhone/iPad remains the final acceptance target.

Older version-labelled reports remain historical artifacts and are not silently counted as current executions.

## v4.7 local-room rule persistence

Focused browser regression:

```sh
python3 tests/local_rules47_browser.py --output tests/results/v4.7-local-rules
```

See `TEST-NOTES-v4.7.md` and `UPDATE-v4.7.md`.

## v4.8 focused grenade motion

```sh
go test -race -count=1 ./...
go vet ./...
node tests/netcode.test.cjs
python tests/grenade48_browser.py --output tests/results/v4.8/browser
```

See `TEST-NOTES-v4.8.md`.
