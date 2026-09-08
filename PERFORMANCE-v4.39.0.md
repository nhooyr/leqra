# Ordered wall-query candidates

## Change

Multi-cell collision queries previously gathered wall IDs from every touched
cell, deduplicated them with per-wall stamps, and sorted the collected IDs for
every query. Sorting preserved authoritative wall order, including the winning
wall and merged normals at an exact corner tie.

The client now sets one bit per candidate wall, then reads the bits in ascending
wall order. This removes the repeated sort and preserves the identical ordered
candidate set. The existing single-cell cache and full-maze fallback remain in
place. The mask is cleared before every multi-cell query and rebuilt with the
existing source/count/dimension invalidation rules.

No intersection formulas, tolerances, projectile limits, or laser damage rules
change in this optimization.

## Measurements

Baseline: commit `6920707` (v4.38.0). Node.js v24.19.0 on Linux amd64. The fixture
runs the production maze generator with a fixed seed, producing an Ultrawide
24 × 14 maze with 294 wall rectangles. Both revisions receive identical seeded
query lists. Each result is the median of seven samples of 40,960 queries after
five warm-up samples.

| Query family | Operation | Before, μs/query | After, μs/query | Time reduction |
| --- | --- | ---: | ---: | ---: |
| Short movement sweep | Candidate lookup | 0.3233 | 0.1668 | 48% |
| Short movement sweep | Complete ray query | 0.4107 | 0.2601 | 37% |
| Bot aiming sweep | Candidate lookup | 1.2648 | 0.4546 | 64% |
| Bot aiming sweep | Complete ray query | 1.6909 | 0.8023 | 53% |
| Long laser/scope-style sweep | Candidate lookup | 3.2016 | 0.8354 | 74% |
| Long laser/scope-style sweep | Complete ray query | 4.7982 | 2.4232 | 49% |

Movement queries have small displacements and a tank-sized radius. Aiming
queries extend up to 420 units on each axis. Long sweeps use a random direction
and length equal to maze width plus height. These lists include queries using
the unchanged single-cell or full-maze paths; the improvements apply to the
whole listed workload, not just selectively timed optimized branches.

These are isolated JavaScript wall-query measurements. They exclude complete
simulation, laser tank intersection/damage, browser painting, and networking.
They do not establish a game-FPS or mobile-performance improvement. Timing on a
shared machine varies. Baseline and optimized benchmark checksums are identical.

## Verification

Five new regressions verify:

- Exact candidate membership and original wall order across all six maze sizes.
- Exact hit times, normals, wall identity, and wall-between-centers results
  against exhaustive sweeps: 4,050 seeded ray cases.
- High-bit boundaries at IDs 31, 32, 63, and 127, duplicate suppression across
  several cell bins, and corner ties.
- Clearing between successive queries and preserving the single-cell cache.
- Index invalidation when maze identity, wall count, or dimensions change.

Together with existing Godlike and movement/prediction checks, **55 JavaScript
tests passed**. Syntax and `git diff --check` also passed.

Reproduce:

```sh
git show 6920707:web/game.js > /tmp/leqra-v438-game.js
LEQRA_SPATIAL_SOURCE=/tmp/leqra-v438-game.js node tests/spatial439.bench.cjs
node tests/spatial439.bench.cjs
node --test tests/spatial439.test.cjs tests/godlike426.test.cjs tests/netcode.test.cjs
```

Raw evidence is under `tests/results/v4.39.0/spatial-performance-*.json` and
`spatial-performance-tests.tap`.
