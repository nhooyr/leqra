# leqra v4.17 — current verification

Current verification is documented in **TEST-NOTES-v4.17.md**. The final full Go run
with the race detector recorded **461 top-level tests passing**, **864 passing
test/subtest events**, **2 existing opt-in skips**, and **0 failures**. The
JavaScript/networking suite has **56 passes**. Focused Chromium adds **12
branding/migration assertions**, **16 desktop gameplay assertions**, and **6
narrow-mobile assertions**, with no uncaught browser errors. Go vet, JavaScript
syntax checks, and the compiled Go build also pass.

```sh
go test -race -count=1 -json ./...
go test -shuffle=on -count=5 ./...
go vet ./...
node --check web/theme.js
node --check web/netcode.js
node --check web/game.js
node --test tests/*.test.cjs
python3 tests/branding417_browser.py --output tests/results/v4.17-final/branding
python3 tests/polish415_browser.py --output tests/results/v4.17-final/desktop
python3 tests/polish415_mobile_browser.py --output tests/results/v4.17-final/mobile
go test -run '^$' -bench '^BenchmarkRoomBroadcast35$' -benchmem -benchtime=500ms -count=3
go build -trimpath -o leqra .
```

Older version-labelled reports remain historical artifacts and are not silently counted
as current executions.

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
