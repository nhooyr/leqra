# leqra v4.17 test notes

## Complete correctness/race pass

The final release-version `go test -race -count=1 -json ./...` run passed **461 top-level tests**, **864 passing test/subtest events**, **2 existing opt-in skips**, and **0 failures**. The run completed with the race detector enabled across the full Go suite, rather than only a targeted subset. `go vet ./...`, JavaScript syntax checks, the compiled `leqra` binary, and **56/56 Node tests** also passed.

New v4.17 regression tests verify that Pickup Rate Off leaves the authoritative spawn clock dormant and creates no pickups, and that the optimized 60 Hz snapshot serializer is byte-for-byte identical to the canonical serializer across live simulation steps on Compact, Large, Giant, and Ultra Wide maps.

A separate randomized serializer stress pass compared canonical and optimized packets across **90 games × 120 live steps** spanning all six map sizes and Elimination/KOTH/CTF configurations; no wire mismatch occurred.

## Browser regression/stress

Final Chromium checks passed:

- **12/12** branding/storage-migration assertions;
- **16/16** v4.15 desktop gameplay/HUD assertions;
- **6/6** narrow-mobile assertions;
- no uncaught errors in those focused runs.

A separate local-simulation stress pass ran **3,600 fixed physics steps** for every combination of all six map sizes and Elimination/KOTH/CTF (18 runs). Tank positions/angles remained finite and inside the arena tolerance, with no uncaught browser errors.

The optimized local A* planner was compared directly with the unmodified v4.16 planner using the same deterministic maze/random stream across **80 position/projectile cases**. Every resulting path matched.

## Benchmarks

On the release environment (Linux/amd64, Intel Xeon Platinum 8573C):

| Benchmark | v4.16 | v4.17 |
| --- | ---: | ---: |
| Eight hard bots, Huge — allocations | 30–33 allocs/op | **0 reported allocs/op** |
| Eight hard bots, Huge — bytes | ~1,959–1,986 B/op | **~74–76 B/op** |
| Room broadcast — allocations | 50 allocs/op | **2 allocs/op** |
| Room broadcast — bytes | ~14,661–14,668 B/op | **~5,349–5,355 B/op** |
| Room broadcast — time | ~31–42 µs/op in representative v4.16 samples | **~24–25 µs/op** in three 500 ms v4.17 samples |

Microbenchmarks are machine- and load-dependent. The allocation reductions are the most stable comparison; they do not guarantee a particular client FPS or public-server capacity.

## Commands

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
