# leqra v3.5 — performance measurements

These are controlled local measurements, not results from the user's device and
not a universal FPS, latency, bandwidth or hosting-capacity guarantee. The shipped
raw summaries are in `tests/results/performance-v3.5.json` and the benchmark files.

## Browser: remove redundant UI work

The same deterministic setup was run for eight seconds with four tanks in a
12×10 local King of the Hill maze. Tanks were invulnerable to hold the workload
stable, so this is a **light-combat** profile, not a worst-case projectile battle.
Chromium used a 1365×950 viewport, default graphics, and a roughly 60 Hz animation
cadence. Both versions' game assets were injected into an isolated page; the
scenario reseeds randomness before configuring/starting the same rules.
A MutationObserver counted changes under `.app`; CDP sampled JavaScript CPU work.

| Metric | v3.4 | v3.5 |
| --- | ---: | ---: |
| DOM mutations in the interval | 6,687 | 2,043 |
| Mean animation-frame interval | 16.701 ms | 16.700 ms |
| 95th-percentile frame interval | 16.80 ms | 16.80 ms |
| Frames longer than 25 ms | 1 | 1 |

That is **69.4% fewer observed DOM mutations**.
Both builds were already approximately 60 FPS here: do not read this as a 69%
FPS improvement. The redundant UI work was verified, but the user's exact
choppiness has not been reproduced on their hardware.

A separate final v3.5 eight-tank run, also light combat at 12×10, recorded a
16.735 ms mean interval, 16.80 ms 95th-percentile
interval, and 2,139 DOM mutations. The intermediate eight-tank CPU
profile identified exhaustive tank/wall collision checks as a hotspot. The final
code queries indexed nearby walls and re-queries after pushes while preserving
original wall order and collision results. It does not reduce physics tick rates.

Repeat with the optional Playwright/Chromium test dependency:

```sh
python tests/performance35_browser.py /path/to/v3.4/leqra-online output/before 4
python tests/performance35_browser.py . output/after 4
python tests/performance35_browser.py . output/eight 8
```

## Go: encode once per room, not once per recipient

`BenchmarkRoomBroadcast35` has four active tanks, 16 spectators, a 12×10 map and
12 missile records. Recipient update queues coalesce normally. The old path
prepares/marshals the snapshot once per member; the new path prepares/marshals it
once and shares immutable encoded bytes. It measures preparation, JSON encoding
and enqueueing—not real network transmission, TLS, rendering or whole-server load.
Three 2-second benchmark trials were run per version on this Linux amd64 container.

| Mean of three trials | v3.4 | v3.5 |
| --- | ---: | ---: |
| Time per room broadcast | 409.0 µs | 21.1 µs |
| Allocated bytes per broadcast | 267,711 | 13,724 |
| Allocations per broadcast | 1,082 | 56 |

This isolated operation is **about 19.4× faster**, with about
94.9% less allocation. **The game as a whole is not claimed to be
19× faster.** Every connected client still needs its own network delivery.
Old and new snapshots share the same scenario; the new version naturally has the
expanded eight-score array even when only four tank seats are occupied.

The final `BenchmarkEightBotsHuge35` advances eight Fierce bots on a 14×12 hill
map, including combat and normal match cycling. It averaged **30.6 µs per
simulation step** across three trials on this machine, with 2,006 allocated bytes
and 31 allocations per step. This is a single-game CPU microbenchmark, not a
worst-case guarantee or a multi-room public-server capacity test.

```sh
go test -run '^$' -bench 'Benchmark(RoomBroadcast35|EightBotsHuge35)$' \
  -benchmem -benchtime=2s -count=3
```

The baseline benchmark source is retained in
`tests/fixtures/room-broadcast-v3.4.go.txt` for copying into an extracted v3.4
source folder as a `_test.go` file. It is not compiled into the new server.

## Collision and network guardrails

The Go suite compares indexed rays against exhaustive wall iteration over
**19,200 rays**, and tank collision resolution over **38,400 positions**, across
all four map sizes. Browser checks compare another **2,000 rays and 4,000 tank
positions** with exhaustive reference routines. Existing movement, powers,
friendly-fire, self-hit, team/objective and spectator tests also run.

The unchanged `web/netcode.js` still provides input replay and buffered remote
interpolation. The final delayed-network check passed for **both local pilots**,
including another participant changing role three times and automatic reconnect.
It injects 60 ms base delay in each direction plus ordered 0–65 ms message jitter.
It is not an actual WAN packet-loss test. See `tests/results/network-v3.5.json`.

## Remaining limits

Eight tanks, projectile effects, GPU/browser limits and other processes can still
consume time. Larger maps also make movement look smaller when fitted on the
same display. The FPS overlay helps separate low render cadence from delayed
online state; Performance graphics trades pixel density/glow for less drawing
work. Actual tank speed, controls, hitboxes and simulation rates are unchanged.

No physical phones, Safari/Firefox, public-host capacity, real network loss or
Docker execution were measured. A single room benchmark does not validate the
configured room cap. Profiling the actual slow device would be needed to identify
its dominant bottleneck; there is no claim that every code path is optimal.
