# leqra v2.7 — ricocheting lasers and remote grenades

> Historical feature guide. **GAMEPLAY-v3.1.md** supersedes its Fire bindings, Player 2 name/HUD, grenade-contact rules and missile tuning.

## What changed

### Ricocheting laser

Laser shots now reflect off walls, including corners. Each shot has one total
travel budget of **2 × (maze width + maze height)**: the perimeter of the current
maze. Bouncing does not replenish the budget. The same calculation uses the
actual maze dimensions in online, solo, and local two-player modes.

The beam is still instant. It stops at the first vulnerable opponent, with a
shield absorbing the hit; it does not pierce tanks. The shooter's existing laser
immunity is retained, including on reflected segments. In solo mode, bot lasers
pass through other bots and their shields without damage. Normal/Fierce bots
can look for laser bank shots.

The pickup still gives **three shots for up to ten seconds**, with a **0.85-second
cooldown**. Firing uses the existing Fire button. The server traces the entire
path and resolves damage, then sends the complete reflected path as one cosmetic
beam event. All clients draw the same segments rather than a line through walls.

Collision tracing starts at the tank centre so a barrel resting against a wall
cannot shoot through it. The first up-to-28 world units inside the barrel are
hidden visually but count toward the budget. Thus the visible beam never exceeds
the perimeter. A defensive 128-segment ceiling also bounds pathological traces.

### Grenades: press to throw, press again to detonate

**Press Fire once to throw. Release it, then press Fire again to detonate your
active grenade early.** The grenade automatically explodes after **five seconds**
without an early detonation. This works with Space, the mobile Fire button, and
player two's Enter key.

A hold launches only one grenade; it never immediately detonates or repeats the
throw. A detonation also consumes that button press/hold, so it cannot also shoot
or throw. Release and press again for the next throw. Other weapons retain their
hold-to-fire behaviour.

Detonation is available immediately after launch, even during the throw cooldown.
It uses **no additional grenade charge** and is restricted to the living tank
that launched the grenade. It still works after the last charge, the weapon's
equip timer expires, or another weapon is collected. An active grenade takes
priority over firing the newly equipped weapon on that next press. When there
are multiple owned live grenades, one detonation press triggers them together.

The mobile button becomes amber and says **BOOM**, with an accessible detonation
label. The HUD shows **DETONATE** and the remaining fuse. This remains visible
for the final grenade even after the weapon returns to standard. The five-second
fuse ring replaces the previous 1.6-second ring.

Grenades still roll, slow down, and bounce without contact damage. The explosion
can damage the thrower and multiple opponents; **walls block the blast and shields
absorb a hit**. Dead tanks cannot remotely detonate, but their already-launched
grenades retain the fuse. Solo bots can choose early detonations against the
player and remain immune to bot-team damage.

Online detonation and damage are server-controlled. The browser sends Fire button
edges immediately. The server latches a short press/release that occurs between
simulation ticks, derives ownership from the authenticated connection, and does
not accept client-provided detonation targets or damage reports. Held/stale inputs
are not treated as new detonation presses.

### Room hint

The **“Leave blank for a random room.”** hint beside the Join area is removed.
The existing blank-name Create Room behaviour, arbitrary-text room names,
automatic invite URLs, direct joins, host kicks, and callsign editing are retained.

## Update the game

Stop the current server. Keep a backup of any custom deployment settings, then
replace **both the Go sources and the complete `web/` directory** with this
package. From the extracted folder:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. `/healthz` and `leqra.version` report **2.7.0**.
Do not mix old clients and the new server: older clients draw a single straight
laser line and show obsolete grenade controls/fuse information. Restarting clears
in-memory rooms and scores. Existing invites can recreate fresh rooms as before.

For a compiled deployment, rebuild because the web assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. For an existing Docker Compose deployment, keep
custom settings and run `docker compose up --build -d`. There are no new game
runtime dependencies or build steps. This is an updated source package, not a
newly hosted public server.

## Verification

Passed **147 Go tests with the race detector** (231 including subtests),
**22 JavaScript networking tests**, **65 production WebSocket checks**, and
**281 browser assertions**. Go vet, JavaScript syntax checks, and a compiled
server build passed. The delayed-network turning/reconnection regression passed.
The movement-smoothing module is byte-for-byte unchanged from v2.6.

See **TESTING.md** and `tests/results/*-v2.7.json` for the checks actually run.
New Go tests exercise reflection geometry, the total perimeter limit, full-path
serialization, shields and cover, launch/hold/release semantics, five-second fuse
expiry, last-charge and changed-weapon detonation, ownership, short taps, stale
inputs, and round cleanup. New browser checks use the shipped code with four
real server-backed clients, including simultaneous touch steering/firing.

Tests use Chromium desktop/mobile emulation and local Go sockets. Because this
environment blocks browser navigation, the browser harness injects the shipped
assets with synthetic location/History/storage adapters. Physical phones,
Safari/Firefox, public internet hosting, Docker execution, and actual address-bar
navigation have not been tested. Server authority and smoothing cannot eliminate
real connection latency; remote detonation takes effect when the server processes
the press.
