# leqra v4.25.0 verification

## Final checks

- `go test -race -count=1 -json ./...`: **493 top-level tests; 913 including subtests**, all passed.
- `node --test tests/*.test.cjs`: **92 passed; 0 failed**.
- `go vet ./...`: passed.
- `go build -trimpath`: passed with Go 1.23.12.
- Every shipped JavaScript file passed `node --check`.
- All HTML asset entrypoints resolve to packaged files; root source JS/CSS and production asset copies match byte for byte.
- `git diff --check`: passed.

## New regression coverage

`server425_test.go`: room rename round-trip reconnect; disconnected/closed rematch controllers and renewed consent; identical immutable broadcast payloads.

`simulation425_test.go`: lethal own-grenade stop; exact weighted-route parity across 600 seeded maze/roster scenarios; scratch resizing, same-cell and unreachable paths.

`results425_test.go`: FFA/team winning participants spectating, swapping, leaving and rejoining during the final delay; frozen scores and report; nonfinal round progress; new-match reset; clinched queue winner returning to their party without forfeiting the result.

`tests/input425.test.cjs`: C/Enter movement and cross-pilot fire conflicts; default aliases; duplicate labels; accurate solo field-manual instructions.

`tests/result425.test.cjs`: frozen local result/score and original winner through role/seat changes; stable member matching; ordinary nonfinal round progress; next-match reset; restart after a clinch.

`tests/roster425.test.cjs`: preserved controls/drafts, patched readiness/connection labels, selective row replacement, changed member/permission/mode handling, reordering, independent moderation cache, unique free-seat notice and the local grenade-death stop. After 100 unchanged updates, the fixture records only its 3 initial row creations, zero replacements and zero extra DOM attachments. Unrelated readiness/connection/score changes likewise preserve the other controls.

## Benchmark interpretation

Benchmarks ran on Linux/amd64, AMD EPYC 9V74. The route comparison used identical benchmark scenarios before/after replacing the search algorithm. For 24×14, baseline runs were 118262 / 116460 / 117219 ns/op; optimized runs were 6136 / 6481 / 6449 ns/op. All were 0 B/op and 0 allocations/op. A later final-source rerun is included in `benchmarks.txt`.

The full-gallery broadcast comparison measured roughly 2.04 ms, 779 KB and 17615 allocations before; roughly 108 µs, 64 KB and 870 allocations after. Timing varies by workload and hardware. These results do not establish overall FPS, maximum user counts or end-to-end latency.

## Scope

Node UI tests execute shipped functions in a controlled DOM fixture. Browser automation and physical iPhone, Android and Safari testing were not run for this release. Historical browser screenshots/results retain the version labels of the runs that produced them; they are not new v4.25 browser passes.
