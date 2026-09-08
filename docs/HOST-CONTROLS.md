> Historical guide: command paths below reflect its original release. For the current repository layout and commands, use the [setup and development guide](README-verbose.md).

# leqra v2.3 — host kick controls

> Historical v2.3 update notes. The current v2.4 package and its changed missing-room behavior are described in [JOIN-OR-CREATE.md](JOIN-OR-CREATE.md).

## Use the new controls

**In the room:** the host sees **KICK** beside every other player, including
players whose connection is being restored. Select a player, check the callsign
in the confirmation, and press **KICK PLAYER**. Cancel or Escape closes the
confirmation without sending a kick.

**During a match:** open the room/menu button, then use **HOST CONTROLS** to select
a player. The match continues while this menu or confirmation is open.

Only the current host can kick. Guests do not see Kick buttons, and the Go server
rejects forged guest requests. A host cannot kick themselves; use **Leave room**.
When host responsibility transfers, the controls transfer with it. Confirmation
requests identify the particular occupant, not just a reusable seat number, so
a stale request cannot remove a replacement who joins the same slot.

A kicked pilot is removed immediately, their controls are cleared, their tank is
eliminated, and their active projectiles are removed. They receive a removal
message and return to the online menu. Their reconnect credential is invalidated,
automatic retries stop, and the client clears the stored session and invite URL.
A tab-local guard prevents a stale invite from immediately auto-joining on refresh
when session storage is available. A lost notification is handled on reconnect,
without converting the revoked credential into an invite-based fresh join.

**This is a kick, not a permanent ban.** A player may deliberately press Join again
with the room code or open an invite in a fresh session when a seat is available.
There are no accounts or identity/IP bans. Existing match rules still apply:
retired combat slots are not reused partway through a match, new entrants spectate
until the next round, and other players keep their scores and readiness. Removing
the last opponent resolves the round; with fewer than two connected players the
game returns to the lobby after the round result.

Desktop, portrait phones and landscape phones have the same controls. Compact
host lobbies omit the redundant own-player row because **YOUR CALLSIGN · HOST**
and the Ready button already identify the host; all other pilots remain listed.

The v2.1 movement smoothing, v2.2 callsign editing, direct invite joins, matching
Join/Create buttons, offline solo bots, and local keyboard duels remain included.
`game.go` and `web/netcode.js` are byte-for-byte unchanged from v2.2.

## Apply the update

Stop the old server, keep a backup of custom deployment settings, and replace
**both the Go source files and the entire `web/` directory** with this package.
Then run:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. The server restart closes existing in-memory
rooms; create a new room and share the new invite link. The health endpoint and
`leqra.version` in the browser console should both report **2.3.0**.

For a compiled deployment, rebuild because the browser files are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. For an existing Docker Compose deployment:

```sh
docker compose up --build -d
```

This is an updated source package for your server, not a newly hosted service.

## Verification

Passed **76 top-level Go tests with the race detector**, **16 JavaScript networking
tests**, **34 live production WebSocket checks**, and **110 browser assertions**
(46 kick checks, 47 earlier room-flow checks, 17 multiplayer/mobile/offline checks).
`go vet` and JavaScript syntax checks also passed.

New checks cover host-only authorization, self-kick rejection, room isolation,
stale and malformed targets, seat reuse, disconnected players, lost removal
notifications, no automatic rejoin, manual rejoin, host handoff, active tank/shot
cleanup, round resolution, all match phases, bounded notification metadata, and
simultaneous leave/kick handling. Browser layouts covered desktop, 390×844,
320×568 and 844×390 screens, with checks for unobscured menu actions.

Browser testing used Chromium emulation with the exact shipped assets, synthetic
invite URLs and in-memory test storage, connected to a real loopback Go fixture.
The environment blocks direct browser navigation. Production WebSocket permissions
were also tested separately through the normal HTTP handler. Physical phones,
Safari/Firefox, real refresh/deep-link lifecycle, public hosting, Docker execution,
and a new smoothing benchmark were not tested. See [TESTING.md](TESTING.md) and
`tests/results/*-v2.3.json` for details.
