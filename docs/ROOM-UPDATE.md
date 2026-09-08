> Historical guide: command paths below reflect its original release. For the current repository layout and commands, use the [setup and development guide](README-verbose.md).

# leqra v2.2 — room improvements

> Historical v2.2 update notes. The current v2.4 package and its changed missing-room behavior are described in [JOIN-OR-CREATE.md](JOIN-OR-CREATE.md).

## What changed

**Edit your callsign after joining.** In the room, use **YOUR CALLSIGN → SAVE**
(or press Enter). During a match, open the room/menu button for the same editor.
The updated name appears for every player without rejoining or changing your
seat, score, tank, ready status, or movement history. Names can be changed more
than once and are remembered on the device when browser storage is available.
Names support up to 16 letters, numbers, spaces, hyphens, or underscores; the
server removes unsupported characters and rejects an empty result.

**Invite links join automatically.** Opening a valid invite connects immediately
with the visitor's saved callsign, or **PILOT** if none is saved. No extra Join
click or callsign prompt is required. A valid recent session resumes its existing
seat. Expired credentials can fall back to a fresh seat; a copied-tab credential
never takes over another connected pilot. Full, closed, or malformed rooms show
an error instead of retrying endlessly. Invites still need the reachable address
of the running Go server; `localhost` cannot invite another device.

**Join matches Create Room.** Both buttons now use the same lime-green primary
style, including matching hover/pressed/disabled styling.

Players still press **I'M READY**, and the host starts the match. Joining an
ongoing match uses the existing spectator-until-next-round behavior. Opening the
in-match menu does not pause the battle or make your tank invulnerable.

The v2.1 smoothing improvements, mobile steering/firing, solo bot squad, and
local two-player mode remain intact. The underlying Go gameplay simulation and
JavaScript smoothing module are unchanged from v2.1.

## Apply the update

Stop the current server, keep a backup of custom deployment settings, and replace
the project with the new `leqra-online` folder. Update **both the Go source and
all of `web/`**. Then run:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. Existing rooms reset when the server restarts,
so create a new room and share its new invite link.

A compiled deployment must be rebuilt because the web files are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

On Windows, build as `leqra.exe`. Docker Compose deployments should rebuild:

```sh
docker compose up --build -d
```

`GET /healthz` and `leqra.version` in the browser console report **2.2.0**.
This is source for your server, not a newly hosted public service.

## Verification

57 Go tests passed with the race detector, 16 JavaScript networking tests passed,
and 24 live WebSocket checks passed. Browser checks passed all 47 new room-flow
assertions and 17 existing multiplayer/mobile/offline assertions. Layouts covered
1365×950 desktop, 390×844 phone, 320×568 compact phone, and 844×390 landscape phone.

Browser testing used Chromium emulation with exact asset injection, synthetic
invite URLs, and test-only in-memory storage, connected to a real loopback Go
fixture. Actual URL navigation is restricted in this environment. No physical
phones, Safari/Firefox, public hosting, or real-device deep-link lifecycle was
tested. The previous smoothing benchmarks were not remeasured. See [TESTING.md](TESTING.md)
and `tests/results/` for test details and limitations.
