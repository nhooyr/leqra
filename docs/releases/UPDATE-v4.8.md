# leqra v4.8 — grenade motion matched to the 10-second fuse

## Grenades keep moving until detonation is near

The previous grenade used one constant exponential drag coefficient for the entire
10-second fuse. That tuning came from the earlier, much shorter fuse and made a grenade
lose most of its speed far too early: after five seconds it retained only about 11% of
its launch velocity.

v4.8 replaces that with a **late-fuse braking curve**. A grenade now rolls/bounces with
only light drag through the first seven seconds, then progressively brakes harder as the
fuse approaches zero.

Approximate retained speed on an unobstructed throw:

| Time since throw | Fuse remaining | Launch speed retained |
| ---: | ---: | ---: |
| 5 s | 5 s | ~88% |
| 7 s | 3 s | ~84% |
| 8 s | 2 s | ~76% |
| 9 s | 1 s | ~44% |
| 10 s | detonation | ~11% |

This keeps a long-fuse grenade mobile for most of its life without turning it into a
permanently fast projectile. Wall bounces, impact detonation, manual detonation, the
10-second fuse, 220-unit blast, shields, friendly fire and self-damage are unchanged.

## Prediction parity

The drag curve is integrated analytically between two fuse times rather than applying
an approximate fixed coefficient per frame. That makes the result independent of the
simulation step size and keeps these paths consistent:

- authoritative Go multiplayer physics
- local/offline browser physics
- bot grenade trajectory forecasting
- short online projectile extrapolation between snapshots

## Install

Replace the Go sources and complete `web/` directory, then restart:

```sh
cd leqra-online
go run .
```

Refresh every player/spectator. `/healthz` and `leqra.version` report **4.8.0**.
Rebuild compiled/Docker deployments because the browser assets are embedded.
