> Historical guide: command paths below reflect its original release. For the current repository layout and commands, use the [setup and development guide](README-verbose.md).

**Current invite behavior (v4.45.1):** A recognized recent saved session reconnects automatically with its existing callsign and role. New visitors see the join menu with the room prefilled and press JOIN (or Enter) themselves. Fresh spectator invitations likewise wait for START SPECTATING. Expired memberships and host kicks require explicit JOIN again. Rejected credentials return to JOIN without silently allocating a new seat; ordinary background connection recovery remains automatic.


> Historical v2.4 guide. **v2.6 now accepts arbitrary room text up to 128 Unicode
> code points**, not only the six-character alphabet described below. The same
> join-or-create and host rules apply. See [ROOMS-AND-LASERS.md](ROOMS-AND-LASERS.md) for current use.

# leqra v2.4 — join or create rooms

## What changed

**Joining a missing room now creates it automatically and makes you the host.**
The room uses the exact code you entered or opened in an invite, rather than
substituting a different random code.

For example, open Online, enter **ABC234**, and press **JOIN** or Enter. If ABC234
does not exist, you enter a new ABC234 room as its host. Friends joining ABC234
then enter that same room as guests. Opening a direct `?room=ABC234` invitation
has the same behavior, with no extra click or name prompt.

When a room already exists, it joins normally. Its host, pilots, scores, ready
status and match are not replaced. If multiple people join an unused code at
once, the server creates just one room and the first successful join becomes
host. The host keeps the usual start-match and kick permissions.

**Validation and limits remain in place.** Codes must contain six characters
from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. Lowercase is accepted and normalized
to uppercase. Invalid codes, a full four-player room, and a server at its room
capacity show errors; they do not create replacement rooms. Create Room still
chooses a random unused code.

**Old invites work again after a room expires.** They create a fresh room, not a
restoration of old scores, players or match state. Room codes do not permanently
reserve ownership. An explicit invite with an expired saved session can retry
once as a fresh join. Background-only reconnection never silently creates a new
room, steals an existing host, or turns an expired credential into a new one.
The existing kicked-session and no-automatic-rejoin protections are preserved.

Movement smoothing, host kicking, editable callsigns, matching Join/Create
button colors, mobile controls, offline bots, and local two-player mode remain
included. The simulation and movement smoothing files are unchanged from v2.3.

## Apply the update

Stop your existing server. Keep a backup of any custom deployment settings and
replace **both the Go sources and the entire `web/` directory** with this package.
From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. Server restarts close in-memory rooms; old valid
codes and invite links can now recreate those rooms, with the first visitor as
host and all scores reset. `/healthz` and `leqra.version` should report **2.4.0**.

For a compiled deployment, rebuild because the web assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. An existing Docker Compose deployment can rebuild
with `docker compose up --build -d`. Keep custom hosting settings. Players keep
using your server's reachable LAN or public address; this package does not
create a new hosted service.

## Verification

Passed **90 top-level Go tests with the race detector**, **16 JavaScript
networking tests**, **44 production WebSocket checks**, and **128 browser
assertions**. `go vet` and JavaScript syntax checks also passed.

Browser checks used Chromium desktop and phone emulation, synthetic invite URLs,
test-only storage, exact shipped assets, and a real local Go server. Ordinary
browser navigation is blocked in this environment. Physical phones,
Safari/Firefox, public internet deployment and a new smoothing benchmark were
not tested. See [TESTING.md](TESTING.md) and `tests/results/*-v2.4.json` for the recorded
checks and limitations.
