# leqra v3.4 — stable arena, friendly fire and sudden death

## 1. Power-ups no longer resize the maze

The speed/shield status line previously appeared only while a buff was active.
That changed the ammunition panel's height. Because the arena occupies the space
left above the panel, its height changed too, and the resize observer correctly
rescaled the canvas into that smaller space. This was a layout bug, not the speed
power-up changing the map or the multiplayer server moving walls.

The HUD now reserves fixed rows for both locally controlled pilots, including the
weapon and buff line. Speed/shield labels, grenade fuses, cooldowns, missile-lock
warnings and elimination states fit inside those rows. Compact layouts use short
`SPD` and `SHD` labels with full descriptions in their title text. The canvas also
avoids reallocating its backing surface when its pixel dimensions are unchanged.

The map still responds to a real window resize, screen rotation, fullscreen
change or an explicitly different host-selected map. It does not resize just
because a pickup is collected or expires. Adding/removing a second local pilot or
switching into spectator view can intentionally change which HUD panels exist.

## 2. Host-controlled friendly fire, correct self-damage

Open **RULES & MODE → Allow friendly fire (teammate damage)**. It defaults to
**off**, applies to all modes, transfers to an online room and is included in saved
room presets. Older presets without the field retain the default off setting.
Only the host can change it, between matches; an active match must first return
to setup. Changing it clears remote player readiness like other match rules.

**Off:** bullets, missiles, lasers and grenade blasts do not damage other tanks
on the same numbered team or consume their shields. **On:** those weapons can
hurt teammates, with shields and spawn protection still working normally.
Free-for-all opponents are enemies regardless of this switch.

**Self-damage is separate from friendly fire.** Every tank seat, on every team,
can be damaged by its own returning shells, missiles and grenade explosions.
This includes the secondary local player and bots. The old bot-only self-immunity
is removed. The normal launch grace, shields and spawn protection still apply.
Lasers retain their established shooter immunity, including reflected segments;
this update does not turn lasers into self-damaging weapons.

Bots and homing missiles still deliberately target enemies, not their allies,
even with friendly fire enabled. Ally damage is a possible consequence of the
shot or blast, not permission for a teammate's seeker to hunt you. Grenades still
explode on living-tank contact (including protected teammates), but whether that
blast actually damages a teammate follows the friendly-fire rule.

## 3. Hide the sidebar and expand fullscreen play

Use the **sidebar icon beside Fullscreen** in the desktop header. Its tooltip
switches between **Hide sidebar** and **Show sidebar**. Hiding removes the whole
sidebar column rather than leaving an empty reserved space. Scores remain in the
arena header; room, spectator and settings controls remain available.

The choice is remembered in this browser when local storage is available. Phones
already omit the sidebar, so they do not need another toggle. Desktop fullscreen
also removes the large page headline and footer and lets the arena use the
remaining viewport. The whole maze is fitted without stretching or cropping;
letterboxing remains when the chosen map and screen have different aspect ratios.
Hiding the sidebar never changes the maze, physics or network coordinates.

## 4. A proper winning-team popup

At match completion, players and spectators see **CONGRATULATIONS!**, the winning
team or independent pilot, the winning members' names, and the final scores.
Sudden-death victories explicitly say the last surviving side won. This is a
once-per-match modal, not a popup that reopens with every network snapshot.

**BACK TO ROOM** dismisses it without creating a new room, starting another match,
changing spectator roles or transferring host authority. The host starts the
next game using the existing room controls. A new match closes any old result
popup still open in another browser. Individual elimination round wins keep the
short round-result banner; the popup is for winning the complete match.

## 5. More visible Capture the Flag flags

Flags now have a larger numbered pennant, a contrasting outlined backing, a
bright ground marker, and explicit team/status labels. They are drawn in a
foreground pass above tanks so they are not hidden behind a carrier or base.
The symbol has a minimum screen-space size, keeping it legible on small phones.

A carried flag follows its carrier above the tank with a visual tether and a
**CARRIED** label. A dropped flag is marked **DROPPED** with its return timer.
Bases remain marked separately. These changes are visual only: pickup/capture
radii, obstruction checks, team rules and flag-return timing are unchanged.

## 6. No random GO banner during objective matches

The online renderer subtracted time since the newest snapshot from the server's
phase timer. A requestAnimationFrame timestamp can be slightly earlier than a
snapshot receipt timestamp measured with performance.now(). A negative elapsed
value therefore turned a zero phase timer into a tiny positive value, and the
old HUD interpreted it as a new GO banner. This could appear around any incoming
update, not just a death, respawn or projectile.

Elapsed snapshot time is now clamped to zero or greater. Separately, **GO** is
controlled by a short, one-shot countdown-to-play transition, not by the sign of
a general timer. Deaths, respawns, impacts and pickups cannot restart it. Joining
an already-running match also does not create a new countdown. Sudden death uses
its own compact persistent status bar rather than a large centre-screen GO.

## 7. Objective ties enter sudden death

At a tied time limit in **Capture the Flag** or **King of the Hill**, the game
stays in the same room and maze and changes to **SUDDEN DEATH**. If one side
already leads at time expiry, that side wins normally.

Each currently available active combatant receives **one fresh final life**,
including someone who was waiting to respawn. Weapons, shields and boosts reset;
old projectiles and pickups are cleared. Normal brief spawn protection gives
players time to react. Subsequent pickup spawning follows the host's usual rules.
Spectators remain spectators and are not placed in tanks.

Flag captures and hill scoring stop. Scores remain tied on the scoreboard;
**survival is now the tiebreaker**. Flags/hill visuals are removed, the clock shows
**SD**, and the status bar says **LAST SIDE STANDING · NO RESPAWNS**. Bots switch
from pursuing objectives to fighting the remaining opposing side.

After a tank dies, it stays out. When only one numbered team—or one independent
Free-for-all tank—has a surviving tank, that side wins the entire match. Dead
teammates share their surviving teammate's victory. Joining, returning from
spectating or a host swap during sudden death does not provide an extra life;
the incoming pilot waits for the next match. Removing or spectating the last
opposing combatant can therefore resolve the match by survival.

If every surviving side is destroyed in the same simulation step, the game
repeats the final-life showdown for the original eligible contestants still
available, rather than choosing a winner by seat order. Newcomers cannot enter
that replay. An abandoned room with nobody eligible remaining can still end as
a draw. Starting the next game clears sudden death and restores the chosen
objective rules and normal respawns.

## Apply the update

Stop the old server, keep a backup of custom deployment configuration, and replace
**all Go sources and the complete web/ directory**. From the extracted folder:

```sh
cd leqra-online
go run .
```

Refresh every browser. `/healthz` and `leqra.version` report **3.4.0**. Do not
mix the old client and the new backend: old clients lack the friendly-fire rule,
sudden-death display and updated completion UI.

Rebuild compiled deployments because they embed the browser assets:

```sh
go build -trimpath -o leqra .
./leqra
```

On Windows use `leqra.exe`. Existing Docker Compose deployments can rebuild
with `docker compose up --build -d`, retaining their custom configuration.
Restarting clears in-memory online rooms and scores. Device-local presets,
bindings and sidebar preferences remain where browser storage is available.
This is an updated source package, not a newly hosted public server.

## Verification

**Passed:** 294 Go tests with the race detector (472 including subtests), 24 JavaScript
networking tests, 143 production WebSocket checks and 452 browser assertions.
Go vet, syntax checks, compiled embedded-asset checks, and delayed-network movement/
reconnection for both local players also passed.

The release reports and exact commands are in **TESTING.md** and
`tests/results/*v3.4*`. The new browser suite reproduces both original UI bugs
against the optional v3.3 archive, then checks the revised client against local
simulation and real loopback Go WebSockets. It tests stable one/two-player HUD
geometry at desktop, portrait-phone and landscape-phone sizes, every pickup,
expiry and death, actual Chromium fullscreen, friendly-fire permissions, flags,
team victory popups, and sudden death for players and spectators.

Go checks cover all seat indices, humans and bots, all weapon damage paths,
shield handling, enemy-only target acquisition, host authorization, frozen
objective scores, no respawns, last-side wins, mutual destruction, late arrivals,
replacement occupants and new-match resets. Historical reports in the package
are version-labelled and are not counted as current test executions.

Browser tests use Chromium desktop/mobile emulation, exact shipped assets,
synthetic Location/History/storage adapters and local servers. Physical phones,
Safari/Firefox, public internet hosting, real packet loss, Docker execution and
hosting capacity are not tested. Native fullscreen is exercised in Chromium;
actual address-bar navigation remains adapted. Synthetic delay results are not
a guarantee for every network. No change is made to the core netcode.js module.

### Timing/layout references

- MDN requestAnimationFrame: https://developer.mozilla.org/en-US/docs/Web/API/Window/requestAnimationFrame
- MDN ResizeObserver: https://developer.mozilla.org/en-US/docs/Web/API/ResizeObserver
