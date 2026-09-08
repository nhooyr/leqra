# leqra v3.3 — spectators, watch links and host swaps

> v3.4 update: see GAMEPLAY-v3.4.md for optional friendly fire, universal shell/missile/grenade self-damage, final-life objective tiebreakers and updated UI. Those rules supersede earlier conflicting descriptions below.


## Watch without taking a tank seat

In the room, select **SPECTATE** beside your callsign. During a match, open the
room/menu button and choose **SPECTATE** there. You stay in the room and watch
the same live arena, but no tank is assigned to you. The spectator banner replaces
your ammunition display, and inactive primary touch controls are hidden.

Select **JOIN AS PLAYER**, or **JOIN PLAY** beneath the arena, to return when a
tank slot is available. The room still supports **four tanks**, including bots
and secondary local players, plus **up to 16 spectators**. The spectator bound
includes disconnected members during their reconnect grace and secondary local
spectators. It is a resource limit, not a tested hosting-capacity guarantee.

Your role is distinct from being eliminated. A dead active player remains part
of the lineup and participates in the next round or objective respawn. A spectator
has no tank, cannot fire or collect power-ups, cannot carry flags or score hill
points, and does not count as a ready vote or opposing side.

### Joining or leaving a running game

Switching to spectating immediately removes that pilot's tank, clears their active
projectiles and controls, and drops any carried flag. It does not restart the game
or remove other members. Missiles cannot retain a lock on the departed occupant.

An incoming player in **Elimination** waits for the next round. In **Capture the
Flag** or **King of the Hill**, they use the configured respawn delay and normal
spawn protection. Toggling out and back in does not provide an extra elimination
life or let a pilot instantly reclaim a loaded tank. Returning to a numbered team
receives its current score; an independent Free-for-all entrant starts at zero.

The host can spectate too, while keeping their host controls. To watch bots fight,
assign at least two opposing sides and start the match. Spectators do not satisfy
the requirement for two opposing sides.

## Share a spectator link

In an online room, use **COPY SPECTATOR LINK** beside the normal invite action.
It is also available in the in-match room menu. The link contains the public room
name plus `spectate=1`, with the room name safely URL-encoded; it never includes a
reconnect token or other private credential.

Visitors see **Watch this room** and must enter or confirm their callsign before
selecting **WATCH GAME**. A previously saved callsign can be prefilled, but the
page does not connect or claim membership until confirmation. An empty or
unsupported-only name is rejected. Pressing Enter in the callsign field also
confirms. Cancel returns to the local room without joining the shared room.

After confirmation, the visitor starts as a spectator even if tank seats are
available. If a game is already running, its live arena appears automatically.
If the room is waiting or between matches, the visitor sees its room screen and
will see the next game when the host starts it.

The existing join-or-create behavior applies to watch links too: a missing room
can be created with the first spectator as its **spectating host**, initially with
no tanks. That host may add bots or choose to play. Opening an old link cannot
restore a deleted room's prior scores or ownership.

As before, invite links require the running Go server at an address reachable by
visitors. On Wi-Fi use its LAN address; outside that network use your public
HTTPS deployment. `localhost` points to the visitor's own device. A spectator link copied there
retains the watch flag but shows a clear localhost-only warning; open the LAN or
public address first to make a link other devices can use. This update does not deploy a public service.

## Full rooms welcome spectators

When all four tank places are occupied, a normal join or normal invite is accepted
as **spectating**, instead of returning the old tank-capacity rejection. The room
and its lineup are unchanged; no player is displaced. The interface explains that
the arena is full and lets the visitor keep spectating.

When a place becomes available, a spectator can choose **JOIN AS PLAYER**. They
are not promoted automatically. If both the arena and spectator gallery are at
their limits, admission still returns a clear capacity error. The server-wide room
and connection limits also remain in force.

## Spectators persist across games and reconnects

Starting another round, choosing **PLAY AGAIN**, or using **End match & edit room**
and then starting another game does not convert spectators into players. Only an
explicit role change or a host swap changes their role.

A brief disconnect reserves membership for the existing **20-second reconnect
grace**. Automatic reconnect restores the accepted spectator role, callsign and
membership rather than allocating a tank. Refreshing a spectator-link page still
asks for callsign confirmation; a valid saved session resumes after confirmation.
If the session has expired, a fresh spectator-link join remains a spectator.

Roles are room/session state, not account storage. Server restarts remove online
rooms and scores. Local rooms reset on reload. Saved key bindings and ordinary
room presets remain browser-local as before; presets do not store spectator
members or reconnect credentials. Loading a replacement preset is disabled while
spectators are present, so loading cannot silently remove or promote them. Existing
individual rules and roster controls remain available to the host between games.

## Everyone can see the spectators

The header's **SPECTATORS N** button opens the named spectator list for everyone,
both during matches and in the room. The room also has an expandable
**SPECTATORS** section. Labels distinguish **YOU**, **HOST**, **LOCAL P2**, and
members who are reconnecting. Callsign edits update these lists for the whole room.

Host controls appear beside each applicable spectator:

- **KICK:** confirms removal, invalidates the reconnect credential, and stops
  automatic rejoining. As before, this is removal, not an account/IP ban; a person
  can deliberately join again in a new session when capacity allows. Removing a
  controller also removes its dependent local player, whether playing or spectating.
- **SWAP:** selects an active human or secondary local player, then confirms an
  exchange. The spectator takes that seat's team and current score; the outgoing
  player becomes a spectator. No active tank, weapon, shield or speed boost is
  transferred. Normal next-round/respawn waiting still applies.

Swaps work even when all four tank seats and the spectator gallery are occupied.
The server validates host permission, both member identities and their current
roles. A stale selection cannot affect a replacement occupant. A disconnected
spectator must reconnect before being swapped into play. The host can swap
themselves without handing their host powers to the incoming player; host authority
follows the member, not the numbered tank seat. Bots are not spectators: remove a bot
to free its tank slot rather than putting it into the spectator list.

Guests can toggle only their own role and their own secondary local player's
role. They cannot force another member to spectate, perform host swaps, or kick
someone by sending a forged command.

## Local second-player support

The local host can watch while the secondary keyboard player continues playing,
or the secondary player can watch while the primary stays active. The active
secondary player retains their own name, ammunition display, bindings and
independent online prediction. Their owner can use **SPECTATE** in the active
roster or **PLAY** in their spectator row.

Sharing a local room carries these roles into its new Go-backed room. A secondary
local player remains attached to the same controller/device through swaps and
host handoff. A remote spectator who takes a former local-player tank controls it
from their own browser; they do not take over the other device's keyboard input.

Local matches keep their normal pause behavior. Opening an online menu or spectator
list does not pause the shared game. A player who merely opens the spectator list,
without switching role, still has a vulnerable tank in the arena.

## Apply the update

Stop the current server, preserve custom deployment settings, and replace **all
Go source files and the complete `web/` directory**. The new `spectators.go` is
required. From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every browser. Both `/healthz` and `leqra.version` report **3.3.0**.
Do not mix old clients with the new backend: old clients assume every room member
has a tank ID and do not understand spectator role changes.

Compiled deployments must rebuild because the web files are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild
with `docker compose up --build -d`, retaining their hosting settings. Restarting
resets existing shared rooms; reconnect grace cannot survive a process restart.
There is no new database, npm step, or third-party game runtime dependency.

## Verification

Passed **277 Go tests with the race detector** (405 including subtests),
**24 JavaScript networking tests**, **143 production WebSocket checks**, and
**340 browser assertions**. Go vet, JavaScript syntax, the compiled server and
embedded asset-byte checks passed. Both local pilots kept moving through three
other-member role changes under injected network delay, and reconnection passed.

See **TESTING.md** and `tests/results/*v3.3*` for the checks run against this release,
including server authorization, role persistence, full-room admission, swaps,
local controllers, callsign prompts and responsive layouts.

Browser tests use Chromium desktop/mobile emulation, the shipped assets, synthetic
Location/History/storage adapters, and real local Go WebSockets. Physical phones,
Safari/Firefox, actual address-bar navigation, public internet hosting, Docker
execution and capacity testing were not performed. Synthetic network delays are
not a promise about every internet connection.
