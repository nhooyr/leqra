# leqra v4.1 — ricocheting Cannon and Ghost

## Cannon: four times larger and faster, with edge ricochets

Cannon rounds still pass straight through **internal maze walls**, without
slowing down or destroying them. They now **bounce off the outer arena boundary**,
including corners, instead of disappearing when they reach it.

| Property | Regular shell | Cannon shell |
| --- | ---: | ---: |
| Collision diameter | 7 world units | **28 world units — 4×** |
| Collision radius | 3.5 world units | **14 world units — 4×** |
| Speed | 282 world units/second | **1,128 world units/second — 4×** |

Four times the diameter also means four times the radius, not four times the
area. The drawn projectile is enlarged accordingly. The larger muzzle clearance
prevents immediate overlap with the launcher. A shot aimed outward while the
barrel is against the rim reflects from the near boundary; it cannot escape
through a seam between border tiles. Swept collision still checks the entire
movement segment, so the faster round cannot skip over a tank between steps.

A pickup still supplies **three shots for up to ten seconds**, with a
**0.85-second firing cooldown**. Launched rounds retain their **5.3-second maximum
lifetime**, which bounces never reset. They stop on the first damage-eligible tank;
a shield absorbs one hit. They do not pierce tanks or cause splash damage.
Friendly fire follows the host setting. **Your own returning Cannon can destroy
your tank after its launch grace**, just like your returning shells.

The normal and Scoped Cannon guides now reflect only at the arena rim, while
passing through interior walls. The guide keeps its own existing distance budget;
it does not extend a Cannon projectile's actual lifetime. Bot shot forecasts and
online projectile drawing also use boundary-only reflections.

## Remove bots in one click

The host's **REMOVE / KICK** action removes a bot immediately, in local rooms and
shared rooms. There is no confirmation dialog for a bot. The server still checks
host permission and the selected participant's identity, so a stale action cannot
remove a replacement occupant. Matched public rooms keep their locked roster.

Removing or kicking a **human**, including a secondary local human, still requires
confirmation. No human-removal or spectator-moderation permission is relaxed.

## New Ghost power-up

Drive over the pale-blue **Ghost** pickup to move through internal maze walls for
**ten seconds of live play**. It activates automatically and has no firing charges.
Your tank becomes translucent with a dashed outline, and its HUD shows a **GHO**
countdown. The maze, settings and legend share the same Ghost icon drawing.

**Ghost is independent of the weapon, Super Speed, Shield and Scope.** You can
phase through a wall at boosted speed while carrying a Cannon or another weapon.
Collecting Ghost again refreshes its timer to ten seconds; it does not replace
another buff, multiply speed or add another ten seconds. Each local pilot has an
independent timer. All four buff timers fit the fixed-height HUD without resizing
the maze, including the small-phone layout.

Ghost does not grant invulnerability, enlarge the arena or remove tank-to-tank
collisions. The **outer boundary remains solid**, and ordinary weapons still obey
their own wall rules. If your tank's centre is inside a wall, ordinary firing is
briefly blocked with **IN WALL · MOVE TO FIRE**, without consuming ammunition or
charges. Move into clear space to fire normally. Cannon can still fire through
walls, and an already-launched grenade can still be remotely detonated.

When Ghost expires inside a wall, the tank is moved to the **nearest safe
cell-interior point** rather than getting trapped or dying. This can be a short
visible nudge. It does not create a new life or award spawn protection. Expiry in
open space does not reposition the tank. Respawns, new rounds and sudden-death
life resets clear Ghost like the other buffs.

Ghost works for humans, bots and the secondary local player in all three game
modes, locally and online. Bots can use it to cross walls toward opponents or
objectives. In online games, **Go owns collection, the timer and wall movement**;
clients cannot grant themselves phasing. Movement prediction, input replay and
remote interpolation are updated for Ghost and its safe expiry. The game still
uses the existing 60 Hz server simulation and 30 Hz state snapshots.

There are now **ten pickup types**. Ghost is enabled in new rooms, built-in
presets and matchmaking's default rules. The host can disable it in
**RULES & MODE → AVAILABLE POWER-UPS**. Existing custom presets keep their explicit
saved selections; enable Ghost and save again to add it. Map sizes, area-scaled
pickup caps, initial stocks and Super fast spawn timing are unchanged.

## Install

Stop the current Go server. Preserve custom deployment settings, then replace
**all Go sources and the entire `web/` folder**, including the new **`phase.go`**.
From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. Both `/healthz` and
`leqra.version` should report **4.1.0**. Update client and server together:
old clients have the wrong Cannon collision rules and cannot predict Ghost.

Rebuild compiled servers because they embed the browser assets:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Rebuild an existing Docker Compose deployment with
`docker compose up --build -d`, retaining the deployment configuration. Restarting
clears in-memory rooms, queues, matches, chat and reports. Browser-local presets,
key bindings and display settings remain where storage is available.

This is source for your running server, not a new hosted multiplayer service.
There are no new game runtime dependencies or database migrations.

## Verification and limitations

The release passed **415 top-level Go tests with the race detector** (800
including subtests), **29 JavaScript networking tests**, **146 production
HTTP/WebSocket assertions** and **121 browser assertions**. Go vet, JavaScript
syntax checks, a compiled build, five embedded-asset comparisons and production
fixture-endpoint exclusion checks also passed.

A **separate synthetic-jitter smoothness benchmark failed its threshold in both
v4.1 attempts**. It is not counted as passing, and no performance improvement is
claimed. The dedicated real-socket Ghost/Cannon test did pass for both local
keyboard pilots, a spectator and reconnection. See **TESTING.md** and
**TEST-NOTES-v4.1.md** for the actual measurements and comparison run.

Browser checks used Chromium desktop/mobile emulation with the shipped assets,
synthetic Location/History/storage adapters and local Go sockets. Physical phones,
Safari/Firefox, physical speaker output, public hosting, actual address-bar
navigation, real packet loss, Docker execution and hosting capacity were not
tested. Synthetic timing runs are not a guarantee for every device or connection.
