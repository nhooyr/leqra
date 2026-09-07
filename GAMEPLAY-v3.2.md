# leqra v3.2 — rules, objectives, presets and control feedback

> v3.4 update: see GAMEPLAY-v3.4.md for optional friendly fire, universal shell/missile/grenade self-damage, final-life objective tiebreakers and updated UI. Those rules supersede earlier conflicting descriptions below.


## Start in the same room

The existing room is still the home screen. **RULES & MODE**, **PRESETS**, and
**CONTROLS** open separate panels, rather than crowding the roster. The default
is still you against two Normal bots in an elimination match. There are still
**four tank seats total**, including bots and any secondary local player.

Everything described below works in local play and in Go-backed online rooms.
The browser simulates local matches; Go owns online rules, movement, weapons,
objectives, damage, respawns, and scores. Clients cannot award points or submit
flag positions. Bots navigate toward objectives as well as fighting enemies.

## 1. Player 2 fires with Space

| Setup | Player 1 | Secondary local player |
| --- | --- | --- |
| Two local humans | WASD + **F** | Arrow keys + **Space** |
| One local human, with bots or online opponents | WASD or arrows; **F or Space** | None |
| Mobile touch | Left thumbstick + Fire button | Hardware keyboard required |

These are the **default** bindings. Enter no longer fires Player 2 by default;
it still submits name fields and other forms. The primary Space/arrow aliases
operate only while no local P2 exists and P1's bindings remain at their defaults.
With two local humans, Space belongs only to P2. Both Fire actions support hold
for ordinary weapons and press/release/press for grenade remote detonation.
Pressing an alias while the other Fire binding is already held does not create
an extra grenade trigger.

## 2. Host-controlled Free-for-all

Open **RULES & MODE → BATTLE FORMAT → Free-for-all**. Applying the rule places
**every human and bot on an independent side**. Individual team selectors become
disabled. A newly joining human or added bot also has no team under this rule.

Only the current host can apply this setting. Guests can open **VIEW RULES** but
cannot edit its fields. Server authorization rejects forged rule and team edits;
this is not just a disabled button. The host must switch the global format back
to Teams before assigning numbered teams again. Switching back gives the host
and its secondary local player Team 1, and other seats Team 2, ready to adjust.

In Teams format the host still controls every seat's numbered team or individual
independent-side choice. Guests do not choose teams themselves. Capture the Flag
requires two numbered teams and therefore disables the Free-for-all format.

Rule and roster changes require the lobby or completed-match screen and clear
remote guest readiness. Use **End match & edit room** to change a live match for
everyone; it resets the current scores, but keeps the room and its invite.

## 3. Missile warnings and cooldown feedback

A homing missile actually locked onto your tank produces a pink **MISSILE LOCK**
warning in your own ammo panel and directional chevrons beside your tank pointing
toward the missile. Each locally controlled pilot has independent warnings;
Player 2 is not shown Player 1's warning as if it were their own. Teammates and
missiles that are not locked onto that pilot do not produce a lock warning.

Warnings follow the live simulation locally and server-reported targets online.
They cannot arrive before the relevant network update. A returning self-fired
missile can still hit its launcher without deliberately seeking them: this is
an incoming *lock* warning, not a guarantee against every dangerous projectile.

**CONTROLS → COMBAT FEEDBACK** has separate visual-warning and warning-sound
switches. Visuals are on by default; the optional sound is off by default.
Global mute also mutes warning sounds. Preferences are saved on the device when
browser storage is available.

Both ammo panels now show **READY**, a numerical **COOLDOWN**, **WAITING FOR AMMO**,
or **DETONATE READY**, plus a progress bar. Objective deaths show **RESPAWN** with
a countdown. On mobile, Fire also has a cooldown ring and countdown/WAIT label.
An armed grenade's BOOM/detonation state takes priority, even during a throw
cooldown. Lasers use their charges rather than being blocked by old shell slots.

## 4. Saved room presets

Open **PRESETS** to load one of five quick setups:

- Solo practice: a compact arena with one Chill bot.
- Local duel: two keyboard pilots in Free-for-all.
- Two humans vs. bots: two keyboard pilots against two Normal bots.
- Capture the Flag: two numbered teams with a human/bot team against two bots.
- King of the Hill: a human and three bots in Free-for-all.

Give the current setup a name and press **SAVE CURRENT SETUP** to keep a custom
preset. Up to **12 custom presets** are stored on this device. They remember
names, the secondary local seat, bot difficulties, teams, match rules, and enabled
weapons. Loading and deletion are available from the same panel. Saving under an
existing name asks before replacing it; deletion asks for confirmation.

Presets never save reconnect tokens, network credentials, active bullets, scores,
or remote guests. Saving an online room omits those remote humans. Loading an
online preset is permitted only when the host is the room's sole network
controller; it refuses to replace remote people, including disconnected people
whose seats are reserved. Change individual rules/roster entries instead while
friends are in the room. Loading creates fresh virtual participant identities,
keeps the host's session, and resets the match.

Presets are browser-local, not account/cloud storage. They survive a normal page
reload when storage is available, but can be lost if browser data is cleared.
The UI reports a failed save rather than claiming it persisted. Invalid stored
settings fall back to usable defaults or fail validation without replacing a room.

## 5. Remappable keyboard controls

Open **CONTROLS**, choose an action under Player 1 or Player 2, and press a key.
Forward, reverse, left, right, and Fire/detonation can all be changed. The room's
control notes and ammo panels display the accepted bindings.

A key already assigned to either pilot is rejected rather than silently creating
conflicts. **Escape** cancels capture; **RESET DEFAULT KEYS** restores WASD+F and
arrows+Space. P/Escape (menu), M (mute), Tab, and system/modifier shortcuts are
reserved. Letter, number, arrow, Shift, Space, Enter, and several punctuation and
numpad keys are supported. Bindings use physical keyboard codes.

Bindings apply only to that browser, including both locally controlled pilots in
an online room. They are remembered separately from room presets. Other players'
keys are not changed by the host. The existing mobile thumbstick and Fire button
remain unchanged; this release does not add gamepad support or a second touch
controller. Editing settings releases gameplay inputs instead of leaving a tank
driving or firing while a dialog is open.

## 6. Host-configurable rules

| Setting | Choices / limits |
| --- | --- |
| Mode | Elimination, Capture the Flag, King of the Hill |
| Battle format | Teams or Free-for-all; CTF requires Teams |
| Maze size | Compact 7×7, Standard 9×8, Large 12×10 cells |
| Score target | 1–20 round wins or captures; 1–300 hill points |
| Time limit | 30–600 seconds |
| Respawn delay | 1–10 seconds, used by the objective modes |
| Pickup frequency | Fast 2–3.5 s; Normal 4–6 s; Slow 7–10 s; Off |
| Enabled pickups | Any subset of all seven power-ups, including none |

The time limit is **per round in Elimination** and **for the whole objective
match** in CTF/Hill. Selecting an objective mode in the UI suggests 180 seconds
and a target of 3 captures or 60 hill points; the host can change them.

When enabled, a match starts with two pickups, subject to valid placement. The
first extra spawn attempt occurs after the selected interval's lower bound;
subsequent attempts use that randomized interval. Five uncollected pickups remain
the cap. Off, or an empty enabled-weapon set, gives no starting or later pickups.
Changing map size also changes missile/laser path budgets using the actual maze
width and height. These are freshly generated connected mazes, not a new map editor.

The Go server validates the whole rules object before applying it. Sharing a
local room includes its configured rules; joining/reconnecting receives those
rules. Applying settings cannot change an active match halfway through a round.
No sudden-death option, public matchmaking, persistent server rankings, or
larger-than-four-player room is added in this release.

## 7. Objective modes

### Capture the Flag

Use **exactly two numbered teams**, with every participant assigned to one. The
room refuses to start an invalid CTF lineup. Each team has a marked base and flag.
Touch an enemy flag to carry it, then bring it to your own base **while your own
flag is home** to score a capture. Teammates share that point, including dead ones.

A killed or removed carrier drops the flag where they were. An ally can touch a
dropped friendly flag to return it; an opponent can pick it up. An unattended
dropped flag returns home after **12 seconds**. Carrying, capture and return
checks respect walls. Spawn-protected players cannot pick up, return or capture
flags during protection.

Eliminated players respawn after the configured delay near their team's base.
The placement routine prefers clear cells and resets weapon, speed and shield
pickups; a **1.2-second spawn protection** prevents an immediate damage hit. A
new entrant in an unused seat waits the configured respawn delay and joins the
current objective match instead of waiting for a nonexistent next round. New
guests join an existing, less-populated numbered team and receive its score.

Bots head for enemy flags, bring carried flags back, and can recover/intercept
their own flag while still fighting. First team to the capture target wins. If
time expires first, the higher capture score wins; tied scores are a draw.

### King of the Hill

A marked hill appears at a reachable central cell. Hold it with your tank's
centre inside the marked area to earn **one point per second**. Multiple allies
do not multiply the rate. As soon as opponents occupy it too, the hill becomes
**CONTESTED** and nobody scores. An empty hill gives no points; contesting or
changing ownership clears the unfinished fraction of the next point.

Both numbered teams and Free-for-all work. Spawn-protected tanks cannot contest
or score until protection expires. Deaths use the configured respawn delay; kills
alone do not end the match. Bots navigate toward the hill while engaging enemies.
First side to the point target wins. At the time limit, a unique highest score
wins; a tie is a draw.

Objective state is included in authoritative snapshots. Respawns use a new life
identifier so local prediction and remote interpolation cannot slide a tank from
its death location into its new spawn. The previous movement smoothing remains
in use for both local keyboard pilots and remote opponents.

## Upgrade

Stop your server, preserve custom deployment settings, and replace **all Go
sources and the entire `web/` folder**. From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. `/healthz` and `leqra.version` should report
**3.2.0**. Rebuild a compiled executable (`go build -trimpath -o leqra .`) or
Docker image (`docker compose up --build -d`): the server embeds the web assets.
Do not mix old clients with the new backend. Restarting resets in-memory online
rooms and scores; saved presets/bindings remain on their individual browsers.

Sharing still requires the Go server at a reachable LAN or public address. This
package is not an already-hosted public server and does not create a tunnel.

## Verification

**Passed:** 250 Go tests with the race detector (378 including subtests), 24 JavaScript networking tests, 114 production WebSocket checks, and 258 browser assertions. Delayed-network movement/reconnection also passed for both local players.

See **TESTING.md** and `tests/results/*v3.2*` for the actual test reports and
commands. Tests use deterministic Go simulations, the production WebSocket
handler, and exact shipped browser assets. Browser tests run Chromium with
synthetic Location/History/storage adapters against a real loopback Go fixture
because ordinary browser navigation is restricted in the test environment.
Physical phones, Safari/Firefox, actual address-bar navigation, public internet
hosting, gamepads, Docker execution, capacity, and real packet loss were not
exercised. The synthetic-jitter regression is not a universal latency guarantee.

Implementation references: MDN KeyboardEvent.code and Window.localStorage
(https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code and
https://developer.mozilla.org/en-US/docs/Web/API/Window/localStorage).
