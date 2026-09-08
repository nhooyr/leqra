# Typed room metadata encoding

## Change

Room broadcasts already encoded one shared packet for all recipients, but each
packet still built a dynamic map for every field of every member. JSON encoding
then sorted those map keys again.

The broadcast now uses typed, public-only room and member records. Their field
order matches the canonical `roomMessage` map encoding byte for byte. Metadata
is still read afresh on every broadcast; there is no persistent metadata cache.
Only immutable encoded bytes enter client queues. Explicit color index zero and
false rematch votes remain present where required, and absent optional fields
remain absent. Prepared color selections and rematch values are copied.

The existing `roomMessage` is retained as the canonical reference, following the
same reference/typed-wire pattern used for movement snapshots. New parity tests
ensure protocol changes cannot silently drift between the two representations.

## Measurement

Baseline: `15eab8c` (v4.42.0). Go 1.23.12, Linux amd64, AMD EPYC 9V74. Both
revisions use the existing `BenchmarkBroadcastRoomFullGallery`: eight pilots,
sixteen spectators, one metadata broadcast to every client, then queue draining.
Results are medians of five runs with 300 ms benchmark duration per run.

| Metric | Before | After |
| --- | ---: | ---: |
| Time per complete broadcast | 105.873 μs | 15.336 μs |
| Allocations per broadcast | 869 | 7 |
| Bytes allocated per broadcast | 63,792 | 10,473 |

The measured operation is approximately **6.9× faster**, with about **84% less
allocated memory**. This applies to full-gallery metadata preparation, encoding
and enqueueing in the fixture. It does not measure movement snapshots, game FPS,
network transmission, or total production-server throughput. Timing varies on
a shared machine; allocation counts were stable across all five runs.

## Verification

Four new tests check byte-for-byte parity across all game modes, FFA/Teams,
lobby/countdown/playing/round-end/results phases, connected/disconnected owners
and local P2, bots, ordered spectators, optional colors, queue and party travel,
true/false rematch votes, empty arrays, and prepared-record independence from
later member edits. Public packets exclude private tokens.

Focused race checks also include the existing queued-broadcast immutability,
rules snapshot and public roster checks. All passed; `git diff --check` passed.

Commands:

```sh
go test -run '^$' -bench '^BenchmarkBroadcastRoomFullGallery$' -count=5 -benchtime=300ms ./src
go test -race -count=1 -run 'Test(RoomWire443|BroadcastRoomWireParityAndImmutableSnapshots|Rules32SnapshotAndRoom|UnifiedRoomAndSnapshotExposeOnlyPublicSeatData|TeamNames36AtomicHostAuthorityAndSnapshot)' ./...
```

Raw benchmark and race output are adjacent to this report.
