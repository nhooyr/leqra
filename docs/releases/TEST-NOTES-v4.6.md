# leqra v4.6 — verification, bug audit and optimization notes

## Executed checks

| Check | Result |
| --- | --- |
| Go race suite | **446 top-level tests passed**, 2 existing opt-in tests skipped, 0 failed; **838 passes including subtests** |
| JavaScript unit tests | **56 passed**, 0 failed |
| Focused v4.6 Chromium assertions | **14 passed**, no uncaught browser errors |
| Retained v4.5 room/browser regressions on v4.6 | **18 passed**, no uncaught browser errors |
| Production WebSocket assertions | **9 passed** |
| `go vet ./...` | Passed |
| JavaScript syntax | `game.js`, `netcode.js`, `theme.js` passed |
| Compiled Go server | Passed |

The two skipped Go tests are the existing opt-in fixture-generation/browser tests. They
are not counted as passes. Machine-readable race output and focused text reports are in
`tests/results/v4.6/`.

## New v4.6 coverage

The focused Go/browser checks cover:

- Q as the stock P1 Fire binding, with Space retained as the no-P2 alias;
- exact half-perimeter Machine gun path accounting including the hidden muzzle segment;
- permanent Machine gun shooter immunity;
- a narrow Giant-map corridor producing **more than 22 ricochets** without premature
  Machine gun termination, followed by correct range expiry;
- no per-round Machine gun trail-history allocation;
- ten-second grenade fuse and 220-unit authoritative blast event/damage radius;
- distinct Laser-versus-Shotgun icon pixels;
- local Restart match from Pause;
- Play Again from the victory popup using the same local room settings;
- no uncaught browser errors in the focused phone layout.

The retained room regression reruns the previous release's callsign, FFA paint ownership,
team-color authority and five-stack Speed behavior against v4.6. The production
Origin-validated WebSocket pass checks FFA paint ownership, denied host repaint,
team-color locking and rejection of client-forged Speed state.

## Bug audit findings

### Fixed: long Machine gun range could be cut short

The ordinary-shell 22-bounce defensive ceiling also applied to Machine gun rounds. A
half-perimeter Machine gun path on the 16×14 map can legitimately exceed 22 reflections
inside a narrow corridor, so the projectile could disappear before the requested range
was spent. Machine gun now uses the larger bounded defensive ceiling; the ordinary shell
limit remains unchanged for the weapons it was designed to protect.

### Fixed: stale rapid presentation trail entry

Machine gun does not render history trails, but an old trail-map entry could survive a
presentation transition while the same authoritative projectile ID remained present.
The rapid branch now explicitly deletes that unused entry.

The race suite also reran existing scoring/death/objective/shield/friendly-fire/spectator
and matchmaking tests. No additional point-award or tank-death defect was found in this
pass. This is a targeted audit with regressions, not a proof that no undiscovered bug
exists.

## Optimization changes

- **No Machine gun history arrays:** live local and remote rapid rounds use a tiny
  instantaneous speed streak rather than append/shift trail arrays every simulation or
  presentation step.
- **O(1) compact color mapping:** the server uses a canonical color-index map instead of
  scanning all eight colors for every compact Machine gun record.
- **Preallocated state slices:** common snapshot slices reserve expected capacity before
  appending tanks/bullets.
- **Reduced blast-outline ray count:** the much larger grenade visual uses fewer radial
  clipping samples, especially under Performance graphics, while preserving wall-aware
  appearance.

The compact decoder remains bounded at 1,536 Machine gun records, enough for eight
players at the new 192-round per-owner cap. No universal FPS/latency percentage is
claimed from these source-level changes.

## Commands

```sh
go test -race -count=1 -json ./... > tests/results/v4.6/go-race.json
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --check web/theme.js
node --test tests/netcode.test.cjs tests/combat42.test.cjs \
  tests/palette44.test.cjs tests/theme43.test.cjs
python3 tests/polish46_browser.py
python3 tests/polish46_regression_browser.py
go build -trimpath -o leqra .
```

With a production server running locally:

```sh
python3 tests/polish46_protocol.py http://127.0.0.1:8466
```

## Limits

Testing uses Chromium desktop/mobile emulation and local Go sockets. Physical phones,
Safari/Firefox, public-WAN deployment, real packet loss, Docker execution, sustained
production capacity, physical audio output and hardware-GPU profiling were not exercised.
Local prediction and rendering improvements cannot remove actual server/network latency.
