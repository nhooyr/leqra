# leqra v4.26.0 verification

## Automated checks

- Full `go test -race -count=1 -json ./...`: **511 top-level tests; 931 including subtests**, all passed.
- Full `node --test tests/*.test.cjs`: **141 passed; 0 failed** on the final JavaScript source.
- `go vet ./...`: passed.
- Production `go build -trimpath`: passed with Go 1.23.12.
- Every shipped JavaScript file passed `node --check`.
- All HTML asset entrypoints resolve. Root source JS/CSS and versioned production copies match byte for byte. Server/browser/PWA versions agree on 4.26.0.
- Final HTTP asset, PWA/cache, version-handshake and theme-entrypoint tests passed after synchronizing the final assets.
- `git diff --check`: passed.

The Go race suite ran against the final Go source. A subsequent JavaScript-only optimization and field-manual cleanup were covered by the final Node run; the production build and asset tests ran after those final assets were copied.

## New and updated regression coverage

`tests/audio426.test.cjs` (12): no native unlock tones on Controls/scroll gestures; trusted activation rules; coalesced resume and retry; idempotent gain and ramps; fallback sample attenuation; muted/delayed/stale effects; bounded queues; interrupted recovery; transient audio-node cleanup.

`tests/input425.test.cjs` (15, updated for the new binding schema): both fire keys; all configured P2 fallbacks after either player remaps; inactive/spectating P2 ownership; conflicts across all twelve mappings; held-key release; current manual labels; legacy and new storage migration; unavailable storage.

`tests/confirmation425.test.cjs` (9): all seven former native prompts; accept/cancel/Escape; safe text, labels and focus; input release; duplicate and delayed-close races; stale room/match/host/setup/preset rejection.

`tests/godlike426.test.cjs` (19): availability and physical limits; grenade remote/fuse/contact/cover cases; safe throwing and detonation; pickup utility and reachable safe routes; CTF recovery/carriers; KOTH holding; homing trajectory prediction and state immutability; weapon threats and laser anticipation; boosted threat reach; ally state handling; 600 seeded collision comparisons for cached single-cell wall queries.

`godlike426_test.go` (17): matching server difficulty validation and tactics, including actual missile and grenade simulations, CTF/KOTH behavior, speed-boost reach, friendly contact, and no mutation during prediction.

`godlike_mode_simulation_test.go`: three deterministic compact-map 2v2 seeds per mode, Godlike versus Fierce, up to 120 simulated seconds per seed, with all ten pickups enabled.

## Bot simulation results

| Mode | Godlike | Fierce |
| --- | ---: | ---: |
| Elimination round points | 16 | 9 |
| CTF captures | 7 | 2 |
| KOTH points | 134 | 29 |

These are smoke-test totals from three seeds, not calibrated win rates, proofs of optimal play, or a substitute for human playtesting. The bot obeys ordinary tank and weapon rules and still has bounded prediction and limited steering candidates.

## Performance evidence

The Go benchmark forces full decisions for eight Godlike bots on a generated 24×14 maze with 80 mixed projectiles. A warmed run measured **5.36 ms per batch**, **0 allocations/op**. At a nominal 75 ms think interval, that is approximately 1.19 ms of planning per 60 Hz tick when amortized; this excludes other physics, networking and rendering. Shared forecasts reduced earlier runs of this same new planner from roughly 10 ms per batch.

The local benchmark compiles the shipped functions into same-realm lexical closures, as in the game's IIFE. It forces all eight decisions and route rebuilds together on an ultrawide fixture. Final Node v24.19.0 measurements over 35 batches after warm-up:

| Workload | Mean | Median | p95 |
| --- | ---: | ---: | ---: |
| No projectiles | 0.470 ms | 0.448 ms | 0.883 ms |
| 80 mixed projectiles | 13.710 ms | 13.242 ms | 18.148 ms |

The heavy fixture was roughly 24 ms before reusing motion predictions and shortlisting four steering candidates for detailed guided-missile simulation. Ordinary bot think times begin staggered, and paths are not rebuilt on every simulation tick. These isolated numbers are not browser frame times or mobile FPS. Initial VM-global-based measurements were discarded because proxy lookup overhead distorted them.

Reproduce with `go test -run '^$' -bench BenchmarkGodlikeEightBotsUltrawide426 -benchmem` and `node tests/godlike426.bench.cjs`. Raw results and test output are in `tests/results/v4.26.0/`.

## Scope and Safari follow-up

Node UI tests execute the shipped functions in controlled fixtures. Browser automation and physical Safari/iPhone testing were not performed. Historical browser screenshots/results belong to their original runs; updating script version expectations is not a new browser pass.

The Safari changes remove a concrete source-level cause of unintended sound. The exact reported static remains a physical-device confirmation item. See `UPDATE-v4.26.0.md` for the diagnosis, Apple/WebKit references and a short retest sequence.
