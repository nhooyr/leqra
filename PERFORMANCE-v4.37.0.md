# Server roster traversal performance

## Change

The 60 Hz room maintenance loop previously built and sorted two independent
roster snapshots every tick, even when nothing changed. Each full roster also
allocated a temporary spectator-ID slice.

The loop now builds one ordered snapshot in caller-owned stack storage and
reuses it to count remaining controllers. It refreshes that snapshot after any
expiration, since removing a primary controller also removes their local P2.
Other `Room.members()` callers keep independent snapshots; their spectator-ID
sorting scratch now stays on the stack too. Public roster order is unchanged.

## Measured results

Go 1.23.12, linux/amd64, AMD EPYC 9V74. Medians of five benchmark runs per case,
300 ms per run. Baseline source: `25b85b3` (v4.36.0). Each room fixture has eight
pilots; the full cases add sixteen spectators. The ordinary lobby case includes
its normal snapshot encoding/delivery every second tick. The parked case is a
private home room reserved while its party is in a match, so simulation and
snapshots are skipped.

| Workload | Before | After | Change | Allocations before → after |
| --- | ---: | ---: | ---: | ---: |
| One full lobby tick | 4.050 μs | 2.325 μs | 43% less time | 5 → 1 |
| One parked private-room tick | 1.340 μs | 0.455 μs | 66% less time | 4 → 0 |
| One independent full member snapshot | 0.547 μs | 0.406 μs | 26% less time | 2 → 1 |

Both room-tick cases remove about 640 bytes of allocation per tick in the full
roster fixture. Independent full snapshots use 192 instead of 320 bytes.
Measurements apply to these server operations, not gameplay frame rate, network
latency, or total production-server throughput. Timing also varies with shared
machine load; allocation counts are the more stable result.

## Verification

The focused Go race suite passed, including new checks for sorted and
independent member snapshots, expired controllers with local P2, empty-room
cleanup, deterministic spectator host election, and multiple-room traversal.
Existing matchmaking, spectator, reconnect, disconnect, and unified-room tests
were included. These tests exercise roster identity and lifecycle behavior;
there are no UI or gameplay-rule changes in this optimization.

Commands:

```sh
go test -run '^$' -bench 'Benchmark(Members|RoomTick)437' -count=5 -benchtime=300ms
go test -race -count=1 -run 'Test(MemberSnapshots437|Tick437|Matchmaking.*|Spectat.*|Host.*|Reconnect.*|Disconnect.*|Unified.*)' ./...
```

Raw results: `tests/results/v4.37.0/performance-before.txt`,
`performance-after.txt`, and `performance-race.txt`.
