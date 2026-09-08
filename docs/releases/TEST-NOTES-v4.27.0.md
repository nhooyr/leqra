# leqra v4.27.0 verification

## Final automated checks

- Full `go test -race -count=1 -json ./...`: **544 top-level tests; 972 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **178 passed; 0 failed**.
- `go vet ./...`: passed.
- Production `go build -trimpath`: passed with Go 1.23.12.
- Every shipped JavaScript file passed `node --check`.
- All nine HTML asset references resolve. Root JS/CSS/SVG sources and their versioned production copies match byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache versions agree on **4.27.0**.
- Final HTTP, PWA/cache, theme-entrypoint and version-handshake tests passed after synchronizing the production assets.
- `git diff --check`: passed.

The final Go race run includes all new server and integration tests. The final Node run includes the subsequent touch-button text change during survival breaks. Historical browser scripts have updated version expectations; this does not constitute a new browser run.

## New regression coverage

`power427_test.go` (6) and `tests/power427.test.cjs` (10): all six map tiers, all ten pickup types, independent buff timers and stack caps, grenade fuse separation, exactly 300 productive machine-gun rounds, blocked/idle fire, pickup refresh, regular weapon expiry, serialized ammunition, respawn cleanup, and online preview budgets for both local players.

`godlike427_test.go` (7) and `tests/godlike427.test.cjs` (10): continued safe advances, co-op approach while firing, retreat hysteresis, cached bank-shot validity, urgent-threat overrides, recovery from stationary aiming, scoring-hill holds, spawn protection and useful replacement pickups. Existing grenade, homing-missile, laser, CTF and KOTH tests remain enabled.

`survival427_test.go` (14) and `tests/survival427.test.cjs` (15): one-to-four-person squads, solo human starts, private enemy identities, escalating enemy counts and boss equipment, pickup settings, unchanged mazes, four-second breaks, revivals, input/hazard clearing, timeout and mutual-destruction losses, victory reports, frozen statistics, late joins, reconnects and spectator ownership. Server coverage exercises actual boss AI on every map size. Two additional room tests cover survival capacity and atomic oversized preset/rules rejection.

`integration427_test.go` (6): Huge-map boss buffs last 15 seconds; machine-gun budget cannot be spent during a break and is cleared on revival; Godlike replaces nearly empty machine guns; the boss indicator clears when only ordinary raiders remain; generated enemies cannot inherit departed-player scores; an earned revival continues when the surviving pilot leaves but another human remains.

The matching local revival regression caught and fixed an ordering bug: squad-wipe detection ran before processing an already-earned wave break. Local and online survival now both finish that break and revive the remaining player.

## Performance measurements

The unchanged stress benchmark forces full decisions for eight Godlike bots in a 24×14 maze with 80 mixed projectiles. A final sequential run measured **2.58 ms per batch**, **0 allocations/op**, compared with the recorded v4.26.0 result of **5.36 ms**. Safe movement bypasses unnecessary steering searches; candidate evaluation stops when it cannot beat the current plan; route and target work is reused.

The local benchmark uses same-realm closures matching the game's JavaScript structure. Node v24.19.0 results over 35 measured batches after warm-up:

| Workload | Mean | Median | p95 |
| --- | ---: | ---: | ---: |
| Eight Godlike bots, no projectiles | 0.456 ms | 0.386 ms | 0.727 ms |
| Eight Godlike bots, 80 mixed projectiles | 12.339 ms | 12.252 ms | 14.072 ms |

These are isolated decision costs, not browser frame times, mobile FPS, or a guarantee that every match will run twice as fast. Both runtimes retain bounded threat forecasts. Survival spawning scans at most 336 maze cells per enemy, only at wave boundaries. Online machine-gun preview counting now uses one pass without temporary filtered arrays. Ordinary snapshot broadcasts avoid an unnecessary objective-state clone; retained snapshots still copy mutable survival state.

Reproduce with `go test -run '^$' -bench BenchmarkGodlikeEightBotsUltrawide426 -benchmem` and `node tests/godlike426.bench.cjs`. Final raw outputs are in `tests/results/v4.27.0/`; the `power/` subfolder contains earlier focused implementation checks.

## UI and device scope

Field Manual fire keys form one nonwrapping group with compact spacing, keeping ENTER alongside Q, C and SPACE. Long custom key names can scroll inside the group. Survival uses the existing rules menu, objective bar, cooldown row and result dialog; the touch fire button displays WAIT during breaks.

Live visual inspection was unavailable because the browser's security policy blocked local and inline previews. UI tests executed the shipped functions in controlled Node fixtures. No new browser screenshots, physical iPhone/Safari audio test, or human gameplay balance study was performed for this release. Godlike's improved initiative is covered by deterministic movement/attack tests; actual difficulty and survival pacing still benefit from playtesting.
