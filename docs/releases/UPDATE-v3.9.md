# leqra v3.9 — wall-piercing Cannon

## Cannon pickup

The new **Cannon** pickup fires a large, fast cannonball straight through maze
walls. It is available in local rooms and Go-backed online games, in Elimination,
Capture the Flag and King of the Hill, for humans and bots.

| Property | Normal shell | Cannon shell |
| --- | ---: | ---: |
| Collision radius | 3.5 world units | **10.5 world units** |
| Collision diameter | 7 world units | **21 world units** |
| Projectile speed | 282 world units/second | **846 world units/second** |
| Wall response | Ricochet | **Pass straight through** |

“Three times as large” means three times the diameter/radius, not three times
area. The visible shell and its hitbox both scale accordingly. The projectile
remains large and fast after the weapon expires or is replaced.

Each pickup equips **three shots for up to ten seconds**, whichever runs out
first. Fire repeats at a **0.85-second cooldown** while held. Use the existing
bindings: Player 1's **F**, Player 2's **Space**, or the mobile **FIRE** button.
With only one local human and default bindings, Space also fires Player 1.
Remapped Fire bindings work unchanged. An already-armed grenade retains its
existing next-press detonation priority.

Cannon is a weapon, so it replaces the currently equipped weapon. It does not
remove Scope, speed or shield buffs. Its ammo display shows available active
projectile slots plus remaining Cannon charges and equip time, just like the
other three-shot projectile pickups. Old active rounds still occupy ammo slots.

## Wall piercing, not tank piercing or splash damage

Cannon shells do not bounce, slow down, or destroy walls. They also pass through
walls at the muzzle when the barrel is pressed against cover. A shell disappears
when it leaves the arena or reaches its defensive 5.3-second lifetime.

The first **damage-eligible, vulnerable tank** absorbs the shot. An active shield
absorbs that one hit and the shell disappears; otherwise the tank is eliminated.
The impact flash is cosmetic and does **not** damage nearby tanks. Spawn-protected
tanks are skipped by projectile hits, consistent with normal shells.

With friendly fire off, teammates and their shields are protected and the shell
passes through them. With friendly fire on, teammates can absorb a hit. The
existing shooter launch grace/self-damage rule remains; no new shooter immunity
is added. Cannon has no homing or ricochet behavior and ordinarily cannot return
to its launcher.

Swept circle collision checks test the entire distance traveled each update,
rather than only the endpoint. This prevents the fast shell from skipping a tank
between updates. Online damage, cooldowns, charges, radii and speeds are owned by
Go; clients cannot submit their own Cannon grants or hits. Eliminations, deaths,
team kills and shield saves use the existing statistics system.

## UI, aiming, bots and settings

Cannon has a copper-colored cannonball-and-speed-lines icon. The same drawing
routine is used in the **legend, maze pickup and rules checkbox**, preserving the
matching-icon behavior. Both local pilots have their own Cannon charge/timer and
cooldown feedback. Collecting it or stacking buffs does not resize the arena.

The dotted guide stays **straight through walls** while Cannon is equipped.
Without Scope it retains its ordinary short range. With Scope it extends toward
the arena edge, subject to the existing half-perimeter budget or an earlier tank
hit; it does not draw misleading wall bounces for this weapon. The guide uses the
larger Cannon hit radius. Other weapons retain their existing guide behavior.

Bots can aim at opponents through cover with Cannon and lead targets using its
actual speed. Dodge forecasts also treat the shell as a larger, faster threat
that is not blocked by walls. Bots still deliberately target opposing sides.
The online projectile renderer uses straight, wall-piercing motion as well; it
does not visually bounce a shot which the server sent through a wall.

There are now **nine pickup types**. Cannon is enabled in new rooms and built-in
presets. The host can disable it in **RULES & MODE → AVAILABLE POWER-UPS**. Shared
rooms and saved presets carry that choice. Existing custom presets retain their
explicit weapon lists: enable Cannon and save again to add it to an older preset.

The five maze sizes, area-scaled pickup caps, starting stocks, Super fast timing,
other weapon tuning, tank movement, objectives and room features remain unchanged.
The movement-prediction/interpolation module `web/netcode.js` is unchanged from v3.8.

## Install

Stop the server and preserve any custom deployment configuration. Replace **all
Go sources and the complete `web/` folder**. From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. The server's `/healthz` and the
browser's `leqra.version` should report **3.9.0**. Update both ends: earlier
versions do not recognize Cannon or its wall-piercing projectile behavior.

For an executable deployment, rebuild because browser assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild
with `docker compose up --build -d`, preserving their custom configuration.
Restarting clears online rooms, scores, chat and match reports; saved browser
presets, controls and display preferences remain when storage is available.
This package updates your running server; it does not deploy a public service.

## Verification

**Passed:** 377 Go tests with the race detector (749 including subtests), 24
JavaScript networking tests, 17 production WebSocket checks, and 220 browser
assertions. The separate synthetic-jitter benchmark missed its timing threshold
in both this build and the unmodified v3.8 control; it is not reported as passing.
The dedicated live Cannon firing/damage/reconnection test passed.

See **TESTING.md** and `tests/results/*v3.9*` / `cannon39-*` for the checks actually
run. Tests cover exact size/speed, multiple walls, muzzle overlap, high-speed swept
hits, first-tank stopping, shields, friendly fire, all eight shooter seats,
charges/cooldowns/expiry, arena cleanup, damage/statistics, bots, guides, defaults,
room permissions and client-state rejection. Browser checks include two locally
controlled Cannons, a remote target, and an online phone-emulated spectator.

Browser testing uses exact shipped assets in Chromium desktop/mobile emulation,
synthetic URL/storage objects and local Go WebSockets. Direct browser navigation
is blocked in this environment. Test-only grants and controlled cover live in
an opt-in, loopback-only `_test.go` fixture; these endpoints do not exist in the
production server. Physical phones, Safari/Firefox, physical speaker output,
public internet hosting, Docker execution and production load were not tested.
No FPS improvement or universal network-performance claim is made.
