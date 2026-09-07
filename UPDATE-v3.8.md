# leqra v3.8 — Giant maze, scaled pickups, and Scope

## 1. New 16×14 maze

Open **RULES & MODE → MAP SIZE → Giant · 16×14**. It works in Elimination,
Capture the Flag and King of the Hill, in local and shared online rooms.

**Large · 12×10 remains the default.** Rooms still allow eight tank seats and
16 spectators. The new option travels with shared rooms and saved presets.
Older presets keep their explicitly selected map and power-up list.

## 2. Pickup caps scale with maze area

The maximum number of **uncollected pickups** is now:

**round((maze columns × maze rows) / 9.8)**

This is cell area, not pixel area. Rounding is to the nearest whole number.

| Map | Area in cells | Starting pickups | Uncollected cap |
| --- | ---: | ---: | ---: |
| Compact · 7×7 | 49 | 2 | 5 |
| Standard · 9×8 | 72 | 3 | 7 |
| Large · 12×10 — default | 120 | 4 | 12 |
| Huge · 14×12 | 168 | 5 | 17 |
| Giant · 16×14 | 224 | 6 | 23 |

The rules panel shows the selected map's starting stock and maximum.

## 3. One additional starting pickup per map tier

New matches and each new Elimination round start with **2 / 3 / 4 / 5 / 6**
pickups as map size increases. The local room's maze preview follows the same
supply rules. Starting placement runs after tanks and CTF spawns are positioned.

Super fast remains the default frequency: the first extra attempt occurs one
second into live play, then at randomized **1–2-second intervals**. Countdown and
local-pause time do not advance this timer. The other frequency choices remain.

Safe placement still avoids tanks and nearby pickups. A full arena or unavailable
safe location can skip a spawn attempt. Uncollected pickups still expire after
19 seconds; the cap is a maximum, not a guaranteed number always present.
**Off or an empty enabled-pickup list produces no starting or later pickups.**

Sudden death retains its existing transition: clear old pickups/projectiles,
give eligible contestants a fresh life, and resume the selected timed spawn
schedule. It does not create another maze or bypass the new area-based cap.

## 4. Scope power-up

The blue **Scope** reticle pickup automatically extends your dotted aiming guide
for **ten seconds of live play**. No extra button is needed.

**Maximum guide path = maze width + maze height = half the maze perimeter.**

The guide reflects off walls, counting every segment toward a single total budget.
The muzzle section counts but is hidden. A vulnerable tank can end the guide
before its maximum; friendly-fire settings determine which tanks block it.
At 16×14, the half-perimeter budget is **2,520 world units**.

Scope is a **separate buff**, not a replacement weapon. You can carry a laser,
missiles, grenades, rapid fire or triple shot while scoped, and also keep speed
and shields. Collecting Scope again refreshes its timer to ten seconds rather
than stacking duration or range. It resets with your next life or round.

Both locally controlled players have their **own extended guides and SCP timer**.
Only your controlled live tanks draw personal guides: opponents' and bots' Scope
pickups do not add lines to your screen, and spectators do not gain a guide.
The ordinary short guide returns after expiry. The existing fixed-height HUD
accommodates the new timer without resizing the arena when a buff changes.

This is a visual aiming aid, **not extra weapon range, damage or aim assist**.
It does not forecast homing curves or grenade drag. Actual projectile lifetimes,
missile steering, damage and firing rules are unchanged. A weapon may therefore
travel less far than the full guide, or turn away from it after firing.

The legend, rules toggle and maze all use the **same Scope icon drawing routine**.
There are now **eight pickup types**. Scope is enabled in new rooms and built-in
presets. The host can disable it under **AVAILABLE POWER-UPS**; existing custom
presets retain their explicit selections rather than silently gaining a weapon.

In online matches, Go owns collection and the Scope timer. Snapshots carry
`scopeTime`; the client computes its own cosmetic guide from that authoritative
state. Client input cannot grant Scope. A reconnect retains an unexpired buff.
The movement-prediction/interpolation module is unchanged.

## Apply the update

Stop the current Go server. Back up any custom deployment settings and replace
**all Go source files and the entire web/ directory**. From the extracted folder:

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. Both `/healthz` and
`leqra.version` should report **3.8.0**. Do not combine an older frontend or
backend with this build: old versions do not recognize the Giant map or Scope.

For a compiled deployment, rebuild because the executable embeds the browser files:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Rebuild an existing Docker Compose deployment with
`docker compose up --build -d`, preserving custom settings. Restarting clears
online rooms, scores, chat and current match reports. Browser-saved presets,
key bindings and preferences remain where browser storage is available.

## Verification

**361 top-level Go tests passed with the race detector** (700 including subtests),
**24 JavaScript networking tests**, **51 live production WebSocket checks**, and
**347 browser assertions** passed. Go vet, JavaScript syntax and an embedded-asset
byte comparison also passed. The production executable returns 404 for test-only
grant endpoints.

The targeted tests cover all five sizes, exact starting stocks and caps, all
three modes with eight tanks, safe spacing, disabled pickups, Scope collection,
stacking, refresh, expiry, respawns, round resets, server permission checks,
preset persistence, bounded/reflected guides, icon equality and stable HUD sizes.
Existing flag and post-match-statistics browser regressions passed. Both local
pilots also passed delayed-network movement, spectator-role-change and reconnect
checks; the networking core is byte-for-byte unchanged.

Browser checks used Chromium desktop/mobile emulation, exact shipped assets,
synthetic URL/storage adapters and local Go servers. Direct browser navigation
is restricted in this test environment. Test-only endpoints are isolated in an
opt-in, loopback-only `_test.go` fixture, absent from the production server.
Physical phones, Safari/Firefox, public hosting, real packet loss, Docker execution
and a fresh FPS/capacity benchmark were not tested. See **TESTING.md** and the
version-labelled records under `tests/results/`.
