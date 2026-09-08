# Server wall-candidate traversal

## Change

The Go server still gathered and sorted candidate wall IDs on every collision
query. It now follows the ordered-mask approach already used by the client:
combine the touched cell bins into a reusable bit mask, then enumerate set bits
in ascending wall order. Single-cell queries read their already ordered bin
directly. The full-maze fallback is unchanged.

This is only a broad-phase optimization. Collision order, narrow-phase formulas,
tolerances, laser damage, projectile ownership, and server authority are
unchanged. Candidate masks are cleared per query and invalidated when the maze
backing slice, wall count, or dimensions change. Current callers read candidate
slices without modifying them.

## Measurements

Baseline `de7ec31` (v4.40.0), Go 1.23.12, Linux amd64, AMD EPYC 9V74. Medians of
five 200 ms runs per case. Both revisions use the same seeded Ultrawide maze and
4,096-query fixture for each query family. The fixture measures complete ray
queries as well as candidate enumeration in isolation.

| Family | Operation | Before, ns/query | After, ns/query | Reduction |
| --- | --- | ---: | ---: | ---: |
| Short movement | Candidates | 91.63 | 83.96 | 8% |
| Short movement | Complete ray | 215.5 | 202.1 | 6% |
| Bot aiming | Candidates | 301.7 | 209.4 | 31% |
| Bot aiming | Complete ray | 948.4 | 778.4 | 18% |
| Long laser/scope-style sweep | Candidates | 728.5 | 427.9 | 41% |
| Long laser/scope-style sweep | Complete ray | 3,162 | 2,828 | 11% |

Both revisions perform zero steady-state heap allocations per measured query.
These measurements cover server wall queries, excluding full AI planning,
simulation, networking, and browser rendering. They are not FPS or total server
throughput measurements. Shared-machine timing varies, particularly in the
small movement case.

## Verification

Four new tests cover 9,216 candidate-set comparisons across all six maze sizes,
6,144 exact ray-result comparisons against the retained exhaustive reference,
high-bit boundaries and clearing, maze/index invalidation, and stable
single-cell candidate slices. Candidate IDs retain exactly the same original
wall order; ray time and corner normals are equal without a tolerance.

The focused race suite passed with existing spatial, laser, cannon, and Ghost
checks:

```sh
go test -race -count=1 -run 'Test(Spatial441|Spatial35|.*Laser.*|.*Cannon.*|.*Ghost.*)' ./...
go test -run '^$' -bench 'BenchmarkSpatial441$' -count=5 -benchtime=200ms
```

Raw results are in `tests/results/v4.41.0/server-spatial-before.txt`,
`server-spatial-after.txt`, and `server-spatial-race.txt`.
