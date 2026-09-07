> Historical v2.8 release notes. The icons and range rules remain; **UNIFIED-ROOMS.md** and **POWERUPS.md** describe the stronger v3.0 missile tuning and teams.

> Historical feature guide. **GAMEPLAY-v3.1.md** supersedes its Fire bindings, Player 2 name/HUD, grenade-contact rules and missile tuning.

# leqra v2.8 — matching icons and dodgeable ricochet missiles

## 1. The legend matches the maze

All seven power-ups — laser, homing missile, grenade, super speed, rapid fire,
triple shot, and shield — now use the **same icon geometry, colors, line weight,
and orientation** in the legend and in the arena. The previous font symbols
have been removed. Both destinations call the same `powerIcon` drawing routine,
so there is no separately maintained lookalike drawing to drift out of sync.

Small high-DPI canvases draw the legend icons. Names and descriptions remain
ordinary readable text; no additional assets or runtime dependencies are needed.
The game's existing responsive layout and touch controls are unchanged.

## 2. Homing missiles survive walls, but can be dodged

Missiles now **ricochet off walls and corners** instead of exploding on contact.
Firing with the barrel against a wall reflects from its near face rather than
spawning through it. A wall bounce clears the target lock and briefly preserves
the reflected heading. Missiles still cannot fly through walls.

The seeker turns more slowly and only tracks opponents ahead of it. **Drive
across an approaching missile's path or get behind cover** to try to break its
lock. When a target moves out of its forward cone or becomes hidden, the missile
coasts briefly instead of immediately snapping around to follow. A correctly
lined-up missile can still hit: a dodge needs enough space and reaction time.
This is not guaranteed immunity from missiles, especially at point-blank range.

Each missile has one total travel budget:

**Maximum distance = maze width + maze height = half the maze perimeter.**

The muzzle segment, curved flight, wall bounces, and small collision-separation
movements all count against that budget. It does not reset when the missile
bounces or changes targets. The missile disappears at the limit, including when
that limit falls partway through a simulation tick. It may disappear sooner
when it hits a tank or the round ends.

The limit uses the actual maze dimensions in each mode. In the usual 9×8 online
maze, width 756 plus height 672 gives a 1,428-world-unit travel budget. This is
**total path length**, not distance from the launch point.

### Rules retained

A pickup still equips **three missiles for up to ten seconds**, using the same
Fire button, Space, or player two's Enter key. The equip timer is separate from
a missile's remaining flight. A launched missile keeps its own budget after the
weapon expires or is replaced.

A missile never deliberately targets its launcher, but a returning missile can
still damage that launcher after the brief launch grace. Shields still absorb
a hit. Solo bots still target only the human and cannot hurt their teammates or
consume one another's shields.

Online guidance, collisions, range, and damage are owned by the Go server.
Offline simulation, bot threat prediction, and the online projectile renderer
have been updated to match. Player movement prediction and smoothing are retained.

Lasers still bounce for up to the **full** maze perimeter. Grenades still have
the **five-second fuse and second-press early detonation**. Faster spawning,
arbitrary room names, automatic invite URLs, direct joins, callsign editing,
host kicking, and reconnection remain included.

### Tuning for developers

| Setting | Value |
| --- | --- |
| Missile speed | 235 world units/second |
| Maximum steering rate | 1.2 radians/second, approximately 69 degrees/second |
| Forward seeker cone | `dot >= 0.25`, approximately 75.5 degrees either side |
| Acquisition range | Six maze cells; requires visibility |
| Lost-lock delay | 0.35 seconds |
| Wall-bounce steering delay | 0.18 seconds |
| Maximum travel | Current world width + height, including muzzle movement |
| Defensive lifetime | Initial travel budget / 235 + 0.5 seconds |
| Defensive bounce ceiling | 128, instead of the ordinary shell's 22 |

The distance budget normally expires before the defensive lifetime/iteration
limits. These safeguards bound exceptional collision cases; they do not refill
range or grant extra damage. Snapshot fields `rangeLeft` and `seekDelay` are
server-owned. The client cannot award itself range or choose a homing target.

## Apply the update

Stop the current server. Preserve custom deployment settings and replace **both
the Go sources and the complete `web/` directory** with this package. Then:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. Both `/healthz` and `leqra.version` should
report **2.8.0**. Do not combine an older browser client with the updated server:
the older renderer still treats missile wall contact as termination. Restarting
resets the in-memory rooms and scores; valid invite names can create new rooms.

Compiled deployments must rebuild because the browser files are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild
with `docker compose up --build -d`, retaining their custom deployment settings.
This is an updated source package for your server, not a newly hosted service.

## Verification

Passed **162 top-level Go tests with the race detector** (253 including
subtests), **22 JavaScript networking tests**, **65 production WebSocket checks**,
and **326 browser assertions**. Go vet, JavaScript syntax checks, and a compiled
server build also passed. The delayed-network turning/reconnection regression
passed; `web/netcode.js` is byte-for-byte unchanged from v2.7.

The icon checks compare the rendered legend against the maze's exact drawing
routine pixel-for-pixel for all seven types at device pixel ratios 1 and 2.
Seven shared deterministic fixtures compare Go and JavaScript positions,
velocities, lock state, remaining range, lifetime, and tank survival. The missile
checks cover muzzle/vertical/corner wall contact, half-perimeter arithmetic,
sub-tick expiry, no range reset, dodge/lock loss, shield and self-hit behavior,
bot-team immunity, bounced AI forecasts, and bounded visual extrapolation.

Live tests use four independent WebSocket clients, including phone layouts and
simultaneous touch steering/firing. The normal-speed sideways dodge and the
full-distance ricochet flight were checked against the real Go simulation.
Only an opt-in, loopback-only `_test.go` fixture grants powers or uses controlled
maps/invulnerability for those trials. These endpoints are absent from the
production server and executable.

**Limits:** testing uses Chromium desktop/mobile emulation with shipped assets
injected into isolated pages, synthetic location/storage/History adapters, and
local Go servers. Direct browser navigation is blocked in this environment.
Physical phones, Safari/Firefox, real internet packet loss, public deployment,
and Docker execution were not tested. A synthetic-jitter regression is not a
latency or hosting-capacity guarantee. See `TESTING.md` and `tests/results/`.

## Implementation reference

The shared renderer uses the standard Canvas 2D drawing context:
https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D
