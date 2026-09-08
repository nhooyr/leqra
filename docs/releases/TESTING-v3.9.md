# leqra v3.9 verification

## Executed checks

- **377 top-level Go tests passed with the race detector**; 749 including subtests.
  The opt-in browser fixture is skipped in ordinary test runs. No Go test failed.
- **24 Node networking tests passed.**
- **17 production HTTP/WebSocket checks passed.**
- **220 browser assertions passed:** 46 Cannon/local/UI checks, 15 live Cannon
  multiplayer checks, 74 map-density/Scope regressions, and 85 flag-label checks.
- JavaScript syntax checks, `go vet ./...`, and `go build -trimpath` passed.
  All five embedded browser assets byte-match the shipped files, and all three
  probed fixture endpoints return 404 in production; see `build-v3.9.json`.

Reports live in `tests/results/*v3.9*`, `cannon39-*.json` and the two timing records.
Other version-labelled reports in the archive are historical, not new executions.

The tests cover 3× diameter and speed, muzzle wall overlap, multiple internal
walls, large timesteps and grazing hits, first-target stopping, shields without
splash, friendly fire in all eight shooter seats, ammo and charges, expiry and
arena exit, bot aiming/dodging, actual pickup collection, Scope guides, matching
icons, stable one/two-player HUD dimensions, rules/defaults/presets and server
authorization. Damage and statistics use the existing full Go regression suite.

The live test runs two local keyboard tanks, one remote target and a spectator.
It observes actual authoritative Cannon shells crossing two walls, a shield save,
a subsequent elimination, independent F/Space fire and charges, and reconnecting
with a secondary Cannon still equipped. Only the explicit loopback `_test.go`
fixture arranges the target/cover and grants the pickup. The production executable
has no fixture endpoints; its normal handler is tested separately for admission,
weapon rules, genuine seeded pickups, timing and forged-input rejection.

## Timing benchmark did not pass

The optional synthetic-jitter test missed its strict remote angular-speed
variation threshold in this environment: **2.501 rad/s** in v3.9, against a
**0.65 rad/s** limit. A control run with the original, unmodified v3.8 archive's
client **and Go server** also failed at **2.406 rad/s**. Both runs recorded zero
backward/near-stopped remote frames and no browser errors, but that does not make
them passing runs. The benchmark stopped before its later role-change/reconnect
checks. The independent Cannon reconnect test above did pass.

This result does not establish a Cannon-specific regression or identify the
cause of the timing variation. The movement-prediction/interpolation module
`web/netcode.js` is byte-for-byte unchanged from v3.8. No FPS improvement,
universal smoothing guarantee, or newly passing latency benchmark is claimed.
Both failed measurements are retained in `tests/results/network39-timing.json`
and `network-baseline38-timing.json` rather than discarded.

## Repeat

```sh
go test -race -count=1 ./...
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs
python tests/cannon39_browser.py --output test-output/cannon39
python tests/scope38_browser.py --output test-output/scope-regression39
python tests/flag_labels_browser.py --output test-output/flags39
```

Start a normal server (`go run . -addr 127.0.0.1:8080`), then:

```sh
python tests/cannon39_protocol.py http://127.0.0.1:8080
```

For the controlled live browser trial, start the fixture in a separate terminal:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:8851 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=15m
python tests/cannon39_online_browser.py http://127.0.0.1:8851 \
  --output test-output/cannon39-online
```

The optional timing benchmark (see the failed results above):

```sh
python tests/network_smoothing.py http://127.0.0.1:8851 --isolated \
  --browser /usr/bin/chromium --local2 --roles --profile jitter \
  --output test-output/network39
```

Python Playwright, Chromium and Python websockets are optional test dependencies,
not game-runtime dependencies. Go tests and the production server need no new
third-party Go modules. Existing map/Scope tests were updated only for the current
version and nine-pickup count; their geometry/supply assertions are retained.

## Limits

Browser tests use exact game assets, deterministic local stepping or real Go
sockets, synthetic Location/storage objects, and Chromium desktop/mobile emulation.
Actual navigation returned ERR_BLOCKED_BY_ADMINISTRATOR in this environment.
Physical phones, Safari/Firefox, physical sound output, public internet hosting,
Docker execution, real packet loss and hosting capacity have not been tested.
The new test endpoint is compiled only in an explicit, loopback-bound test server.
