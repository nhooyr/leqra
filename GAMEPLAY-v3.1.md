> Historical release notes. Current controls, rules, presets and objectives are documented in **GAMEPLAY-v3.2.md**.

# leqra v3.1 — impact grenades, F-to-fire, and two-player HUD

## What changed

### Grenades explode on tank contact

A live grenade now detonates at the first living tank it touches. This includes
rolling into a tank or a tank driving onto a grenade that has slowed to a stop.
The impact is swept along the movement segment, so a fast grenade cannot simply
skip over a tank between physics updates.

The same explosion, not contact damage followed by a second explosion, handles
the hit. **A shield therefore absorbs one hit and the tank survives.** Teammates
and spawn-protected tanks can set off a grenade, but existing team protection
and invulnerability still prevent damage to them. Wrecks do not trigger it.
Human launchers can still be hurt by their own blast. The existing **0.2-second
owner launch grace** prevents immediate self-triggering inside the barrel.

Grenades still bounce from walls instead of detonating on wall contact. Walls
block blast damage. The **five-second fuse** and **press Fire again to detonate**
remain available: impact, remote trigger, or fuse expiry—whichever happens first.
A single grenade generates only one blast. Holding Fire never automatically
detonates or repeatedly launches grenades.

### Player 1 uses WASD + F

| Setup | Primary movement | Primary Fire | Secondary movement / Fire |
| --- | --- | --- | --- |
| One local human, with bots and/or online opponents | WASD or arrows | **F or Space** | Not applicable |
| Two humans on this keyboard | **WASD** | **F** | **Arrow keys + Enter** |
| Phone / tablet | Left thumbstick | Right Fire button | Hardware keyboard required for Player 2 |

F and Space are two bindings for the **same action** when no second local human
exists. Holding one while pressing the other does not create a second grenade
trigger. Release all active Fire bindings before pressing again to detonate.
With two local humans, Space does not fire either tank. Keyboard auto-repeat
cannot manufacture new grenade presses. Very short taps still reach the correct
pilot, even when that pilot occupies a nonadjacent room slot such as seat 3.

**F no longer toggles fullscreen.** Fullscreen remains available from its icon.
Typing in callsign fields does not fire or toggle fullscreen. Input is released
when opening the menu or losing focus. The same bindings are used in local and
server-backed matches; the Go server still receives only logical controls.

### Name Player 2 explicitly

After adding **LOCAL PLAYER 2**, use **PLAYER 2 CALLSIGN → SAVE**, or press Enter
in that field. The same editor appears in the in-match room menu. The name is
shown in the roster, scoreboard, second ammo panel, and other players' views.
Names use the same up-to-16-letter/number/space/hyphen/underscore rules as other
callsigns. Empty sanitized names are rejected. The saved secondary name is
remembered on that device when browser storage is available, independently of
the primary callsign, and is reused when adding Player 2 again.

Online changes are server-approved. Only the controller who owns the secondary
local tank can use this name-only editor, even after host handoff. It does not
change the controller, seat, team, readiness, score, match, or input prediction.
The existing host roster editor can still rename other virtual participants
between matches. Stale occupant references and forged guest requests are rejected.
The current name survives a normal controller reconnect.

### Separate ammunition and loadout displays

Each locally controlled human has a **named P1/P2 panel**, with their Fire binding,
ammunition bars, weapon charges and timer, independent speed/shield timers, and
armed-grenade fuse/detonation status. A dead tank shows TANK DOWN and empty bars.
Both panels update independently in local and online play. A remote guest does
not see another computer's secondary panel as if it were their own.

Normal, rapid-fire, scatter, homing and grenade bars show **free active-projectile
slots**, consistent with the existing game. The weapon label separately shows
special-weapon charges. Laser bars show remaining laser charges. Previously
launched projectiles can still occupy slots after switching weapons.

The two panels sit side by side on a wide screen and stack on a narrow phone.
Player 2's panel and name editor disappear when there is no secondary local seat.

### More aggressive homing missiles

| Setting | v3.0 | v3.1 |
| --- | --- | --- |
| Maximum turn rate | 2.8 rad/s | **4.8 rad/s** (about 71% faster turning) |
| Acquisition range | 8 cells | **10 cells** |
| Seeker direction dot threshold | −0.35 | **−0.75** (wider acquisition cone) |
| Lost-lock coast | 0.12 s | **0.06 s** |
| Bounce steering delay | 0.08 s | **0.04 s** |

Missile speed stays at **235 world units/second**. Steering remains finite; it
is not an instantaneous turn. Walls still obstruct target visibility, missiles
still ricochet, and they never deliberately lock onto their launcher or allies.
Shield and self-ricochet rules are unchanged. They are intentionally harder to
dodge than v3.0; surviving an open-lane encounter is not guaranteed.

The **total path limit remains maze width + maze height—half the perimeter**.
The acquisition range is a separate visibility/search limit; it does not add to
or refill the projectile's remaining travel budget. Curved flight, muzzle
movement, wall bounces and collision-separation nudges still consume that budget.
Go, local browser simulation, and bot missile forecasts use the same new tuning.

## Suggested next improvements (not added in this build)

**Combat feedback:** a cooldown ring on Fire and a brief empty-ammo flash, plus an
optional directional missile-lock indicator and warning sound. These would make
weapon readiness and the stronger missiles easier to read without opening menus.

**Controls and accessibility:** remappable keys, gamepad support, adjustable touch
control size, and team symbols/patterns in addition to colors.

**Saved room presets:** remember names, teams and bot difficulty, and offer one-click
Solo practice, Local duel, and Two humans vs. bots configurations.

**Match options:** host-selected map size/layout, target score, round duration,
weapon toggles and pickup frequency; optional sudden death for drawn-out rounds.

**More objectives:** a later capture-the-flag or king-of-the-hill mode would add a
reason to move around the maze rather than only eliminating opponents.

## Update your server

Stop the current server. Preserve any custom deployment settings, then replace
**all Go sources and the entire `web/` folder**. Do not mix an old browser client
with this backend, since an old client has different grenade contact and missile
rules and does not understand secondary name acknowledgements.

```sh
cd leqra-online
go run .
```

Refresh every player's browser. `/healthz` and `leqra.version` report **3.1.0**.
A restart resets shared in-memory rooms and scores. Existing valid room invite
names can recreate fresh rooms using the same join-or-create behavior.

Compiled deployments must rebuild because the executable embeds the browser files:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Rebuild an existing Docker Compose deployment with
`docker compose up --build -d`, retaining your deployment settings. This is an
updated source package for your running server, not a new hosted public service.

## Tests and limits

Passed **206 Go tests with the race detector** (320 including subtests), **22
JavaScript networking tests**, **93 production WebSocket checks**, and **232
browser assertions** (89 new gameplay/HUD + 143 room regressions). Go vet,
JavaScript syntax and a compiled build also passed. The sequential injected-jitter
movement/reconnection run passed for both local keyboard players.

See **TESTING.md** and `tests/results/*-v3.1.*` for recorded checks and repeatability
notes, including earlier timing-sensitive attempts under concurrent test load.
Browser checks use Chromium desktop/mobile emulation, the exact shipped assets,
synthetic location/storage/History adapters, and real loopback Go WebSockets.
They do not test physical phones, Safari/Firefox, public internet hosting,
real-world packet loss, Docker execution, or production hosting capacity.

The networking core `web/netcode.js` is unchanged from v3.0. The UI uses it for
both locally controlled tanks. Name changes do not reset either predictor.

Keyboard event reference: https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code
