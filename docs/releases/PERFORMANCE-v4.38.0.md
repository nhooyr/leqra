# Player HUD projectile queries

## Change

Each local pilot's loadout and combat-feedback displays previously scanned the
projectile array separately for occupied ammo slots, live grenades, grenade
fuses, and hostile missile locks. A full refresh of both pilots performed ten
array passes when both used slot-based weapons.

`pilotProjectileState()` now collects those values in one pass per pilot per
HUD function. The same refresh performs four passes: **60% fewer projectile
reads**. Missile checks stop once a hostile lock is confirmed, and filtered
grenade/missile arrays and the grenade-fuse mapping array are no longer needed
in these HUD paths. Gameplay firing, damage, and missile-warning drawing retain
their existing functions and behavior.

The summary is temporary, with no cross-frame cache. Local bullets can mutate
between simulation steps, and the HUD always uses the newest authoritative
online snapshot, including during transitions or reconnects.

## Measurements

Baseline: commit `276f5c0` (v4.37.0). Node.js v24.19.0, Linux amd64. The same
fixture executes the production `renderPilotLoadout()` for both local pilots
and `updateCombatFeedback()` once, using a lightweight DOM stand-in. The pilots
use grenade/shotgun loadouts against mixed ordinary, machine-gun, grenade, and
homing projectiles. Each result is the median of seven samples of 5,000 refresh
batches, after five warm-up samples.

| Mode | Projectiles | Before, μs/batch | After, μs/batch | Time reduction |
| --- | ---: | ---: | ---: | ---: |
| Local | 32 | 5.807 | 5.650 | 3% |
| Local | 192 | 8.522 | 7.323 | 14% |
| Local stress case | 768 | 20.146 | 14.226 | 29% |
| Online | 32 | 7.127 | 6.306 | 12% |
| Online | 192 | 9.706 | 8.244 | 15% |
| Online stress case | 768 | 21.132 | 13.688 | 35% |

In the 192-projectile fixture, a full two-pilot refresh reads 768 array entries
instead of 1,920. Read-count instrumentation runs only after all timing samples
to avoid changing V8 array specialization during measurements.

These figures measure HUD JavaScript in this fixture. They exclude simulation,
native browser DOM/layout/painting, network latency, and canvas rendering. They
are not game FPS or phone-performance measurements. Shared-machine timing
varies; the reduction from ten scans to four is deterministic. A live machine
gun hides its slot dots, so its previous loadout path already used one fewer
scan per affected pilot.

## Verification

Six new regressions cover parity with the existing gameplay queries across
weapons and friendly-fire settings; local in-place mutations; newest online
snapshots; owner removal and team changes; independent two-pilot detonation,
ammo and warning displays; and the bounded number of array reads.

Existing machine-gun timer, predicted online-shot, weapon-switch, and lobby
layout checks also pass. Their fixtures now supply actual projectile state to
the consolidated query. At the isolated optimization commit, the full JavaScript suite reported **385 passed, 0 failed**. Final integrated release counts are in `TEST-NOTES-v4.38.0.md`.
JavaScript syntax and `git diff --check` passed. No UI layout or labels changed.

Reproduce against the baseline:

```sh
git show 276f5c0:web/game.js > /tmp/leqra-v437-game.js
LEQRA_HUD_SOURCE=/tmp/leqra-v437-game.js node tests/hud438.bench.cjs
node tests/hud438.bench.cjs
node --test --test-reporter=tap tests/*.test.cjs
```

Raw results are in `tests/results/v4.38.0/hud-performance-before.json`,
`hud-performance-after.json`, and `hud-performance-node.tap`.
