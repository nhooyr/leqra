# leqra v4.4 — verification and limits

## Final executed checks

| Check | Result |
| --- | --- |
| Go with race detector | **444 top-level passes**, 838 including subtests; no failures |
| Opt-in Go fixtures | Two skipped, not counted as passes |
| JavaScript unit tests | **65 passed**, no failures |
| Production HTTP/WebSocket assertions | **22 passed** |
| New gameplay/theme browser assertions | **193 passed** |
| Retained delayed-network online-firing browser assertions | **41 passed** |
| Total browser assertions | **234**, no uncaught browser errors |
| Go vet, three script syntax checks, compiled build | Passed |
| Compiled embedded assets | Seven source/served byte comparisons matched |

The final machine-readable records are in `tests/results/v4.4/`:
`summary.json`, `go-tests.jsonl`, `javascript-tests.txt`,
`production-protocol.json`, `browser-arsenal.json`,
`browser-online-firing.json`, `embedded-assets.json`, and `syntax-check.txt`.
An empty `go-vet.txt` records its successful silent run; see commands below.
Older version-labelled reports are historical and are not included in these counts.

The retained firing suite calls itself v4.2; its report records `suiteVersion`
separately from `testedBuild: 4.4.0`. Its assertions were not loosened. The old
Rapid-fire cooldown unit expectation was intentionally updated to the new zero-
cooldown, 60 Hz weapon specification; the old nine-slot limit is intentionally
96 for this weapon. Shield, appearance, and projectile-size expectations were
updated only where this release changes their specification.

## What the new tests exercise

Shields: one through five pickups/rings, refresh at cap, shared timer expiry,
one charge per eligible hit, ordinary hit grace, no friendly shield loss,
Shotgun self-immunity, once-only death/statistics, and fresh-life resets.
A seeded 60,000-selection test checks the 3:1 weighted chooser; tests also check
weights, singleton pools, disabled Shield, and empty pools explicitly.

Weapons: exact velocities/radii/lifetimes; three Shotgun pellets, five volleys,
wall reflections, all eight owner seats, weapon changes after firing, enemy
hits, and shooter shields. Machine gun tests cover zero cooldown, same-tick
reentry rejection, consecutive ticks, active-slot bounds, a continuous
600-step emitter trial, finite bullet clouds, and eight simultaneous streams.
Those emitter tests directly drive firing/physics to isolate their limits;
they are not an extension of the normal eight-second equip duration.

Networking: compact numeric samples keep the same rounded projectile state,
owner, life and volley identifiers. Node tests exercise bounded malformed-sample
rejection, reconstruction, and independent P1/P2 prediction. The browser uses
real server-backed host/P2/guest/spectator connections, verifies real Machine gun
and Shotgun shots, shield damage, palette state, reconnection and no false
cooldown. The existing online firing regression injects 90 ms delay each way
plus ordered jitter and checks first local previews before acknowledgement,
deduplicated sounds, standard/Cannon non-rewind, grenade ownership, stable
winning feedback, and reconnect cleanup. It is not a new general movement/FPS
or WAN smoothness benchmark.

Palettes: all eight choices, inherited versus per-tank overrides, team-rule
validation, host-only/stale-identity/active-match checks, sharing, presets,
reconnection and report color preservation. Native Chromium light/dark changes
exercise paired colors without changing physics. Pixel comparisons check all
ten icons against the exact shared maze drawing routine in both skins.
A luminance test checks palette separation from the light arena surfaces; this
is not a complete accessibility certification for the whole game.

Layout: 1365×950, 390×844, 320×568, and 844×390, in light and dark. Tests inspect
all five rings, independent displays, full stacked buff text, stable maze bounds,
compact palette selectors and completed-match feedback. Final representative
screenshots were inspected, including the light phone HUD and both lobby skins.

Production protocol probes use the normal Origin-validated handler, with no
fixture-granted powers. They cover palette authorization, invalid indices,
atomic rule errors, authoritative colors, fresh stack state, actual initial
shield-only pickups, and ignored client-forged weapons/charges/colors. The
production executable returns 404 for fixture endpoints.

An initial protocol harness issued administrative probes faster than the existing
eight-actions/second limit. The server closed that connection as designed. The
harness now spaces probes by 180 ms; the same assertions pass. The production
rate limit was not weakened. Interim development runs are not added to final counts.

## Stream payload comparison

One deterministic open-arena test drove eight Machine guns for 240 steps,
with invulnerable tanks to avoid ending the trial early. All streams fired on
every step. Peak live bullets: **712**. At the measured snapshot:

| Encoding of the same 712 rounded projectile states | Bytes |
| --- | ---: |
| Numeric Machine gun records | **32,626** |
| Equivalent previous verbose Bullet objects | **145,122** |

This is roughly **77.5% less projectile-payload data** in that trial. It excludes
other snapshot fields and transport overhead, and compares the same rounded
coordinates/velocities/times. It is **not** 77.5% less total network traffic, a
whole-game speedup, a GPU measurement, or a production hosting-capacity result.

Finite 1.5-second Machine gun bullet life, 96 active slots, one shot per 60 Hz
firing step, bounded decoder/preview history, and reduced cosmetic trails/events
prevent unbounded accumulation. High-rate automatic weapons still cost more than
ordinary low-rate firing, especially with many spectators receiving snapshots.
No maximum public-room count or physical-phone FPS is promised.

## Commands

From the extracted `leqra-online` folder:

```sh
go test -race -count=1 -json ./... > tests/results/v4.4/go-tests.jsonl
go vet ./...
node --check web/theme.js
node --check web/game.js
node --check web/netcode.js
node --test tests/theme43.test.cjs tests/netcode.test.cjs \
  tests/combat42.test.cjs tests/palette44.test.cjs
go build -trimpath -o leqra .
```

Production protocol check (start the compiled server on the selected address):

```sh
./leqra -addr 127.0.0.1:8444
# Separate terminal:
python tests/arsenal44_protocol.py http://127.0.0.1:8444
```

Browser fixture (opt-in Go test only; never a production endpoint):

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:8445 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=0
# Separate terminal, sequentially:
python tests/arsenal44_browser.py --url http://127.0.0.1:8445 \
  --output test-output/arsenal44
python tests/feel42_live.py --url http://127.0.0.1:8445 \
  --output test-output/feel44
```

The optional Python browser tests require Playwright and `/usr/bin/chromium`;
protocol tests require Python websockets. These are development tools, not game
runtime dependencies. The UI harness injects exact source assets with synthetic
Location/History/storage because ordinary navigation is restricted here. It
uses real DOM/canvas/keyboard/pointer code and real loopback WebSockets.

## Not exercised

Physical phones, Safari/Firefox, physical speaker output, native deep-link and
cross-tab storage lifecycles, public internet deployment, real packet loss,
Docker execution, sustained production load, and hardware-GPU benchmarking.
Passing a synthetic-delay regression does not remove real network delay or
prove that every device will run eight automatic weapons without frame drops.
