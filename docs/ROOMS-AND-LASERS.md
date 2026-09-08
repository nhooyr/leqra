> Historical guide: command paths below reflect its original release. For the current repository layout and commands, use the [setup and development guide](README-verbose.md).

# leqra v2.6 — custom rooms, more pickups, and lasers

> Historical v2.6 update notes. For current ricocheting-laser and five-second
> remote-grenade behaviour, see [WEAPON-CONTROLS.md](WEAPON-CONTROLS.md) and [POWERUPS.md](POWERUPS.md).

## The four changes

### 1. Room names can be ordinary text

Use **ROOM NAME / CODE** for names such as `Friday tanks 💥`, `Adam & friends`,
`battle/zone #2`, or text in another language. Spaces, punctuation, emoji, quotes,
and URL characters are accepted. Type the name and press **JOIN**, Enter, or
**CREATE ROOM**. If that room does not exist, it is created and you become host.
If it already exists, you join it without replacing its host or state. Leaving
the field blank and pressing **CREATE ROOM** still generates a random short code.

Names are limited to **128 Unicode code points on one line**. Outer whitespace
is trimmed; internal spaces and spelling are retained. Empty/invisible-only
names, control characters, line breaks, and oversized input are rejected. Most
custom names are case-sensitive. For compatibility, six-character names made
entirely from the old `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` alphabet still use
uppercase, case-insensitive matching: `abc234` and `ABC234` are the same room.
No additional Unicode composition normalization is applied.

The same rules apply to direct invitations and reconnects. Concurrent joins to
a new name produce one room and one host. A readable name is an invitation,
not a password or a permanent ownership reservation. The existing room capacity,
moderation, and reconnect protections remain in place.

### 2. Power-ups arrive faster

Every round starts with **two pickups**. The first extra spawn attempt is **two
seconds into live play**; subsequent attempts happen every **2–3.5 seconds**.
There can be **five uncollected pickups** at once. Placement still avoids tanks
and other pickups, so a full arena or lack of a safe spot can skip an attempt.
Uncollected pickups retain their 19-second lifetime.

This replaces the old single starting pickup, six-second initial wait, subsequent
5.5–8.5-second interval, and three-pickup cap. The new rates apply to online,
solo, and local two-player matches.

### 3. Laser power-up

The pink **LASER** pickup equips **three instant shots for up to ten seconds**.
Use Space, the existing mobile **FIRE** button, or player two's Enter key. Holding
Fire repeats at a **0.85-second cooldown**. The HUD shows remaining charges.

A beam travels instantly in the direction the tank faces, stopping at the first
vulnerable tank or wall, with a maximum nine-cell range (756 world units). It
does not bounce or pierce through another tank. Shields absorb the shot. The
laser cannot hit its shooter, and firing with the barrel against a wall cannot
shoot through that wall. The brief glowing beam is a visual effect, not a
continuous damage zone.

Laser shots do not occupy normal projectile slots, so old bouncing shells do
not prevent a charged laser from firing. A different weapon pickup replaces
the laser; speed and shields remain independent. Charges, cooldowns, and damage
are controlled by Go in online play. In solo, bots can use lasers but still
only target the player; their beams pass through other bots without damage.

All seven power-ups are available: rapid fire, triple shot, shield, homing
missile, grenade, super speed, and laser. See [POWERUPS.md](POWERUPS.md) for the full set.

### 4. The address bar becomes the invite link

After a successful room creation or join, the client updates the current URL
with the accepted room name, using a safely encoded `room` query parameter.
**COPY INVITE LINK** uses the same URL builder. Special characters such as `&`,
`+`, `#`, `%`, emoji, and spaces survive copying and joining correctly.

The update uses `history.replaceState`: no page navigation, reload, or second
connection is requested, and it does not add a history entry per reconnect.
Unrelated query parameters and fragments are removed from the share URL. Only
the public room name is included, never the private reconnect credential.
Leaving or being kicked clears the room query. A restricted History API does
not prevent joining; the Copy Invite button still builds the link.

As before, another device needs your server's reachable LAN/public address.
A URL beginning with `localhost` only works on the hosting device; the Copy
Invite button explains that rather than copying an unusable remote invitation.

## Apply the update

Stop the existing server. Preserve custom deployment settings, then replace
**both the Go sources and the entire `web/` folder** with this package.

```sh
cd leqra-online
go run .
```

Refresh every player's browser. `/healthz` and `leqra.version` report **2.6.0**.
Do not mix old clients with the new server: old clients reject custom room names
and do not understand the laser. Restarting resets in-memory rooms and scores.
An old valid invite can create a fresh room, with its first visitor as host.

Compiled deployments must rebuild because the web files are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild
with `docker compose up --build -d`. No npm or database step is needed. This
package updates your server; it does not deploy a new public service.

## Verification

Passed **126 top-level Go tests with the race detector** (206 including
subtests), **22 JavaScript networking tests**, **65 production WebSocket
checks**, and **234 browser assertions**. `go vet`, JavaScript syntax checks,
and a compiled server build passed. The delayed-network turning and automatic
reconnection regression also passed with the final client.

The new checks cover Unicode/punctuation/128-emoji names, length and control
validation, case rules, host preservation, concurrent creation, resume and kick
safety, encoded invite round trips, URL-update calls, restricted History behavior,
laser walls/shields/charges/cooldowns/expiry, bot immunity, spawn timing/caps,
and simultaneous touch steering/firing. Mobile layouts include 320×568,
390×844 and 844×390; desktop is 1365×950. The movement smoothing module is
unchanged from v2.5.

**Limits:** Chromium desktop/mobile emulation used exact shipped assets,
synthetic location/History/storage adapters, and real local Go WebSockets.
Actual address-bar navigation and real-device deep-link lifecycle were not
exercised; the URL and History call arguments were checked in the adapters.
Production socket validation was separately tested through the normal HTTP
handler. No physical phones, Safari/Firefox, public internet hosting, Docker
execution, capacity test, or real packet-loss test was performed. The jitter
regression is one synthetic run, not a latency guarantee. See [TESTING.md](TESTING.md)
and `tests/results/*-v2.6.json` for recorded checks.

## Implementation references

- MDN, URLSearchParams: https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
- Go standard library, Unicode UTF-8 handling: https://pkg.go.dev/unicode/utf8
