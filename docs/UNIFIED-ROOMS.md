> Historical guide: command paths below reflect its original release. For the current repository layout and commands, use the [setup and development guide](README-verbose.md).

> Historical release notes. Current controls, rules, presets and objectives are documented in [GAMEPLAY-v3.2.md](releases/GAMEPLAY-v3.2.md).

> v3.4 update: see [GAMEPLAY-v3.4.md](releases/GAMEPLAY-v3.4.md) for optional friendly fire, universal shell/missile/grenade self-damage, final-life objective tiebreakers and updated UI. Those rules supersede earlier conflicting descriptions below.


# leqra v3.0 — one room for local players, bots, teams and friends

> Historical feature guide. [GAMEPLAY-v3.1.md](releases/GAMEPLAY-v3.1.md) supersedes its Fire bindings, Player 2 name/HUD, grenade-contact rules and missile tuning.

## Start in a room

The game opens directly into **YOUR ARENA**, a local game room. You are the
host. The default setup is you on Team 1 against Rust and Vapor on Team 2,
both at Normal difficulty. Press **START MATCH** to play immediately; local
play does not contact the multiplayer server.

There are **four total tank seats**, shared by humans, bots and a second local
player. Every participant appears in the same roster. Remove a bot to free a
seat for an online friend. There is no longer a Solo / 2P / Online mode chooser.
The same room UI manages both local and shared sessions.

## Host controls

**Add a second local player:** press **+ LOCAL PLAYER 2**. This creates a second
human tank on the same device and initially uses the host's team. Only one
secondary local seat is supported per room. Its name and team can be edited.
It uses a keyboard on that device, not a second phone thumbstick.

| Player | Move / turn | Fire |
| --- | --- | --- |
| Primary human | WASD; arrows also work when no secondary local player exists | Space, or the mobile Fire button |
| Second local human | Arrow keys | Enter |
| Primary human on a phone | Left thumbstick | Right Fire button |

Both keyboard players can move and fire together, including in a shared online
match. Each has separate server-acknowledged input history and client prediction.
With a second local player, arrow keys no longer also move the primary tank.
Grenades use throw, release, then Fire again to detonate for either player.

**Add bots:** choose **Chill, Normal, or Fierce**, then press **+ ADD BOT**.
Each bot has its own difficulty selector and editable name. Existing bots can
have their difficulty changed without removing them. Chill has slower reactions
and simpler tactics; Normal and Fierce add evasive movement and bank-shot
planning. Shared-room bots run on the Go server, not on a player's browser.

**Assign teams:** every roster row has a host-only selector for **Team 1–4** or
**Free-for-all**. Matching numbered teams share a color, are protected from
teammate damage, and earn the same round point even if one teammate was
eliminated. Free-for-all makes that individual a separate side; it does not
put everyone choosing that option on a single team.

Bots target opposing sides. The default two-bot squad still only fights the
player's side and cannot harm one another. Assigning bots to opposing teams
allows them to fight each other. Human self-ricochets and own grenade blasts
are still dangerous; bot self-damage remains disabled. Lasers retain their
existing shooter immunity. Friendly hits do not consume shields.

A match needs at least **two opposing sides**, and the first side to five round
wins wins the match. The host's Start click is their ready confirmation; other
connected online humans must press **I'M READY**. Bots and the secondary local
player do not require a separate ready action. Changing the shared roster or
teams clears guest readiness so guests consent to the new configuration.

Add/remove/edit controls are available before a match or after it finishes.
During play, the host can open **MY ROOM / the room name → End match & edit
room**, confirm, and bring everyone back to the room with scores reset.
Shared matches keep running while a menu is open; local matches pause.
Host kicking remains available during shared matches.

## Share the configured room

Enter an optional room name and press **SHARE ROOM ONLINE**. The Go server
creates that room and imports the roster, bot difficulties, names and teams.
The local secondary player remains controlled by the host's keyboard. The
address bar becomes the invite URL, and the button changes to **COPY INVITE
LINK**. Friends opening the link join directly into the same room.

Sharing happens from the room, **not halfway through an active round**. Return
to the room first. It transfers the setup, not a running local simulation,
projectiles, or scores. Starting the shared match creates a fresh server maze.
The server validates the setup; clients cannot import damage or winning scores.

A blank name generates a random unused room code. Arbitrary single-line Unicode
names, punctuation and emoji are supported, up to 128 code points as before.
If another room already uses the name, **Share refuses to overwrite or merge it**
and leaves your local setup intact. Choose another name or use **Join another
room**. The separate Join/Create dialog retains the existing join-or-create
behavior: a missing name creates that room, while an existing name joins it.

Sharing requires the included Go backend. It does **not** deploy a public host,
open router ports, or create an internet tunnel. On Wi-Fi, everyone opens the
server's printed LAN address. For friends elsewhere, use your publicly reachable
HTTPS deployment. A localhost URL cannot invite another device. Opening
`web/index.html` directly still supports local play, but not online sharing.

## Ownership, removal and reconnecting

Only the server's current host can edit the shared setup, add participants, end
the match for everyone, or kick/remove a participant. A guest cannot forge a
team change or control someone else's tank. Each edit/removal identifies the
particular occupant, not just a reusable slot number.

The secondary local tank is tied to the controller who added it. Disconnecting
that controller releases both sets of controls; the existing 20-second reconnect
grace can restore both. Host responsibility can transfer to another connected
human, but neither a bot nor a secondary keyboard seat becomes a network host.
An automatic host handoff does not steal the original controller's local tank.
When that controller leaves, is kicked, or expires, its dependent local seat
is removed too. Bots remain available for remaining players. The new host can
remove an old secondary seat and add their own. Kicking is still removal, not
an identity ban.

Rooms and scores remain in memory. Local roster changes are session-local; the
callsign is remembered when storage is available, but local room configurations
are not persisted across a reload. Online reconnect can restore a current room.
Server restarts remove shared rooms, and old valid invite names may create fresh
rooms with a new host as before.

## More aggressive homing missiles

| Setting | v2.8 | v3.0 |
| --- | --- | --- |
| Maximum turn rate | 1.2 rad/s | **2.8 rad/s** |
| Acquisition range | 6 cells | **8 cells** |
| Seeker threshold (direction dot product) | 0.25 | **−0.35** |
| Lost-lock coasting delay | 0.35 s | **0.12 s** |
| Wall-bounce steering delay | 0.18 s | **0.08 s** |

Missiles acquire opponents across a wider angle, turn more than twice as quickly,
and resume seeking sooner. Their turning remains bounded, not an instantaneous
snap. Cover still breaks line of sight, and they never deliberately lock onto
teammates or their launcher. They are intentionally harder to dodge than v2.8;
the previous close sideways escape is no longer reliably safe.

Speed stays at 235 world units/s. Wall and corner ricochets stay enabled, and
**the total path budget remains maze width + maze height: half the perimeter**.
Turning, bouncing, and reacquiring do not refill it. Returning missiles can
still hit their human launcher, and shields absorb a hit. Each pickup gives
three missiles for up to ten seconds.

The seven shared legend/pickup icons, full-perimeter bouncing laser, five-second
remotely detonated grenade, speed boosts, fast pickup spawning and previous
network smoothing remain included.

## Apply the update

Stop your existing server. Keep a backup of custom deployment settings and
replace **both the Go sources and the complete `web/` directory**.

```sh
cd leqra-online
go run .
```

Refresh every player's browser. `/healthz` and `leqra.version` should report
**3.0.0**. Existing in-memory rooms and scores reset when the server restarts.
Do not mix the old frontend with this backend: it lacks the new roster and
secondary controller behavior.

For compiled deployments, rebuild because the browser assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can use
`docker compose up --build -d`, retaining their custom configuration. No new
runtime packages, database, npm step, or third-party Go modules are needed.

## Verification and limits

Passed **191 Go tests with the race detector** (289 including subtests), **22
JavaScript networking tests**, **82 production WebSocket checks**, and **143
browser assertions**. Go vet, JavaScript syntax and a compiled build also passed.
See [TESTING.md](TESTING.md) and `tests/results/*-v3.0.*` for the new runs, including mixed
roster ownership, team protection/scoring, server bot simulation, per-controller
inputs, sharing, mobile layouts, missile parity and delayed-network movement.
The core `web/netcode.js` smoothing module is unchanged; the client integration
now maintains independent prediction for the secondary pilot.

Browser checks use Chromium desktop/mobile emulation, the exact shipped assets,
synthetic Location/History/storage adapters, and real loopback Go WebSockets.
They do not test physical phones, Safari/Firefox, actual address-bar navigation,
public internet deployment, real packet loss, or host capacity. Synthetic delay
measurements are individual runs, not a promise about every connection.
