# leqra v4.17 — bug fixes and performance pass

## Fixed: Pickup Rate Off still ran a spawn timer

When Pickup Rate was set to **Off**, spawning was correctly blocked, but the local and authoritative simulations still woke the pickup scheduler periodically and consumed random-number work just to discover that spawning was disabled. The disabled interval is now infinite, so no periodic spawn attempt runs while pickups are off. Gameplay output is unchanged except that the dormant feature now actually stays dormant.

## Faster authoritative simulation

Collision-heavy AI code no longer allocates a `RayHit` object for each wall query. Production raycasts now return value results, while compatibility wrappers remain for older regression fixtures. Bot A* pathfinding, dodge forecasts, and grenade-threat forecasts reuse buffers attached to each bot instead of rebuilding cost/previous/closed/penalty/threat slices every think cycle.

Elimination side detection and King of the Hill ownership checks no longer build a map each physics tick. Grenade remote-detonation selection uses a fixed three-slot buffer, matching the weapon's maximum active capacity. These changes do not alter collision order, route choice, team rules, or scoring.

## Faster 60 Hz room broadcasts

The authoritative broadcast path now reuses room-owned snapshot slices for tanks, ordinary bullets, compact Machine gun records, and pickups. It encodes a fixed wire struct in the same field order and with the same omission/empty-array behavior as the canonical snapshot. Spectators and players are delivered the same encoded packet without rebuilding and sorting a combined membership slice every tick.

The existing room-broadcast benchmark improved from about **14.66 KB / 50 allocations per broadcast** in v4.16 to about **5.35 KB / 2 allocations** in v4.17. On the same machine during this release pass, v4.17 measured roughly **24–25 µs/op** in three 500 ms samples; v4.16 samples were roughly **31–42 µs/op**. The two remaining allocations are the encoded packet byte slices that must outlive the encoder until socket delivery.

## Lower browser GC pressure

Local bullets, pickups, particles, rings, and traces are compacted in place instead of replacing their arrays with `.filter()` copies. Local elimination/KOTH/sudden-death side checks use primitive scans. Local bot A* planning now reuses typed cost/previous/closed/reserved/danger buffers and queue/path arrays; deterministic comparison against v4.16 produced identical routes across the checked maze/projectile cases.

Online presentation reuses ownership/active/trail ID sets, keeps the render bullet array in place, and prunes shot previews by direct map iteration instead of expanding the preview map into temporary arrays.

## Measured bot-simulation allocation reduction

The retained `BenchmarkEightBotsHuge35` benchmark dropped from roughly **30–33 allocations and ~1.96 KB per simulation step** in v4.16 to **0 reported allocations/op** and about **74–76 B/op amortized** in v4.17 after warm-up. Runtime remains workload/CPU dependent; the important result is removal of the steady-state allocation churn, not a promise of a fixed FPS gain on every device.

## Compatibility

No rule, weapon, movement, networking protocol, room, matchmaking, or saved-setting migration is intentionally changed. v4.15 Ultra Wide, fixed-height pilot feedback, lobby maze preservation, Spectators/Spectating wording, explicit pausing, and pickup lifetime behavior remain intact. v4.16 lowercase **leqra** branding and `leqra.*` storage remain intact.

## Install

Replace all Go source files and the complete `web/` directory, then restart:

```sh
cd leqra-online
go run .
```

For compiled deployments:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh all clients after the server restart because compiled builds embed the browser assets. `/healthz`, `/api/config`, the Controls footer, and `leqra.version` report **4.17.0**.
