# leqra v3.7.2 — defaults and pickup-frequency verification

## Executed checks

- **351 top-level Go tests passed with the race detector** (666 including subtests).
  The opt-in `TestBrowserFixture` is skipped in the normal suite; it is not a
  failed test or included in the pass count.
- **24 JavaScript networking tests passed.**
- **76 focused browser assertions passed** on desktop and phone/tablet emulation.
- **18 live production HTTP/WebSocket checks passed.**
- `go vet`, both JavaScript syntax checks, and a compiled build passed.
- The final executable's embedded HTML, CSS and JavaScript were compared byte-for-byte
  with the shipped files, and `/healthz` reported 3.7.2.

Six new Go tests cover the new default, rule serialization, all three game modes,
first and subsequent spawn intervals, existing frequency compatibility, the
five-pickup cap, disabled pickups/weapon filtering, new-round/sudden-death resets,
host authorization, malformed frequency rejection and match-time rule locking.
An older Fast-tier regression now explicitly selects Fast instead of relying on
an obsolete default. Existing damage/scoring/statistics regressions still run.

Browser checks load the exact shipped assets with test-only URL/storage adapters
and deterministic simulation stepping. They exercise real controls and native
AudioContext oscillator scheduling, preserved opt-outs/global mute, missing and
malformed preferences, saved and built-in presets, all frequency tiers in all
three modes, and phone layouts. The interval label is measured for fit and compact
phone screenshots were visually inspected. No production simulation functions
are replaced by the harness.

Live protocol tests use the normal Go HTTP/WebSocket server, not grant/map test
endpoints. Players and a spectator see the same pickups; the one-second initial
spawn and subsequent 1–2-second intervals are checked against simulation clock
values. Host validation and spectator reconnection are also exercised.

## Commands

```sh
go test -race -count=1 ./...
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs
go build -trimpath -o leqra .
python tests/defaults372_browser.py --browser /usr/bin/chromium \
  --output test-output/defaults372
# With the production server running separately:
python tests/defaults372_protocol.py http://127.0.0.1:8080
```

Python Playwright, Chromium and the Python websockets package are optional test
tools, not game runtime dependencies. Results are in `tests/results/*v3.7.2*`.
Earlier version-labelled reports are historical; they are not counted as new runs.
`TESTING-v3.7.1.md` preserves the preceding release's test documentation.

## Limits

Browser tests use Chromium emulation, not physical phones or Safari/Firefox.
Native sound scheduling is observed, not physical speaker output. Loopback socket
tests do not establish public-host capacity or internet-latency performance.
Docker, actual address-bar lifecycle and a fresh jitter/performance benchmark
were not exercised. The core `web/netcode.js` file is byte-for-byte unchanged.
