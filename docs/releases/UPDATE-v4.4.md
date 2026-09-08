# leqra v4.4 — shield stacks, automatic weapons, and host palettes

## Shields: five charges, five rings

Each Shield pickup adds **one charge, up to five**. The tank shows one concentric
ring per charge; the named ammo panel shows **SHD × N**. A damaging hit consumes
one charge, not the whole stack. The existing 0.35-second post-hit protection
prevents simultaneous pellets from stripping several charges in one impact.
Friendly-fire protection, spawn protection, and weapon-specific shooter immunity
still apply before a shield is consumed.

All charges share the existing **ten-second timer**. Every collection refreshes
that timer, including collection at the five-charge cap. It does not add ten
seconds per charge. Remaining charges expire together, and a new life/round
resets them. Shield remains independent of weapons, Scope, Ghost, and Super Speed.
Both local players have separate counts and rings. Stacked buff labels use fixed
HUD rows and compact text on phones, without resizing the maze.

Shield spawning has weight **3**, while every other enabled pickup has weight **1**.
This is three times the chance of each individual other enabled type—not three
times the combined chance of all the others. With all ten types enabled, Shield
has **3/12 = 25%**, and each other type **1/12 ≈ 8.33%**, on every selection.
Disabled types have no chance. Starting and timed pickups both use these weights.
Map-scaled caps, starting stock, Super fast timing, and placement checks are unchanged.

## Shotgun replaces Triple shot

**SHOTGUN** fires three spreading pellets at **846 world units/second**, three
times the standard projectile speed of 282. Pellet diameter remains **7 world
units**, the same as a normal shell. They ricochet using ordinary wall geometry.

Shotgun pellets **never damage their own shooter or consume that shooter's shields**,
even after bouncing or after the owner changes weapons. Other enemies, friendly
fire when enabled, spawn protection, and shield absorption follow ordinary rules.
The existing **five volleys or eight-second equip timer**, 0.54-second cooldown,
and 3.9-second pellet lifetime remain. The visible name and shared legend/maze icon
are updated. No scatter pellet gains extra damage or wall penetration.

## Machine gun replaces Rapid fire

**MACHINE GUN** fires while Fire is held, with **zero weapon cooldown**.
Each round has **one-third normal diameter** (7/3 ≈ 2.33 world units) and
**three times normal speed** (846 world units/second). Both the collision radius
and the rendered projectile head use the smaller size; a short trail keeps it
visible. Rounds bounce off walls and can still damage their owner after the
normal launch grace. Machine gun does not inherit Shotgun's self-immunity.

Zero cooldown is not an infinite same-instant emission loop: **at most one round
per 60 Hz firing step, up to 60 rounds/second**. The same rate is used locally and
by Go, including when the local physics/render rate is higher. The weapon remains
active for **eight seconds**. Its bullets have a **1.5-second lifetime**, with
**96 active-projectile slots per owner** while equipped. This bounds the continuous
stream while allowing it to sustain fire without a periodic reload when slots
are free. Old projectiles can occupy slots; damage/charge authority remains on Go.
The HUD shows **READY · CONTINUOUS**, not a fake cooldown between rounds.

Existing Fire bindings, remapping, both local players, and mobile Fire work as
before. An already-armed grenade still takes priority on the next new Fire press.
In-wall firing restrictions during Ghost remain, except for Cannon as before.

### Keeping the stream bounded and responsive

Immediate local previews still reconcile with accepted server volleys. Machine
gun uses a bounded preview history and compact numeric projectile samples in the
online protocol. Its trails, muzzle effects, and sound calls are deliberately
throttled; **the actual simulated rounds are not omitted**. Other weapons keep
their existing snapshot objects. The existing movement-input replay rules and
server 60 Hz simulation / 30 Hz snapshot rates are retained.

In a deterministic eight-gun test, all eight streams fired continuously for
240 steps. There were at most 712 live bullets in that particular trial. The
712-bullet numeric payload was **32,626 bytes**, versus **145,122 bytes** for the
same rounded state serialized as the previous verbose bullet objects. This is
a payload comparison, **not a whole-game FPS or hosting-capacity claim**. Eight
simultaneous streams still need appreciably more simulation work and bandwidth
than the old low-rate weapon. No real-device or public-host capacity guarantee
is made.

## Neon-blue dark mode and theme-aware assets

The dark interface primary accent is now **neon blue (#00C8FF)**. Light mode keeps
its **neon-purple (#A100FF)** primary accent. Auto/Dark/Light still follows the
browser preference or the saved manual override under **CONTROLS → APPEARANCE**.

Tanks, walls, pickups, projectile heads/trails, guides, explosions, shields,
flags, hill markers, labels and other effects now use theme-aware paints.
Light mode uses deeper colored assets and contrasting details against pale
surfaces instead of reusing washed-out luminous dark-mode colors. Team numbers,
shapes and identities remain the same. Switching theme repaints existing effects
as well as cached art, without changing physics, room membership, maze dimensions,
held controls, or the network connection. The ten pickup icons still share the
same geometry between maze, legend and rules.

## Host-selected tank and team colors

There are **eight paired choices**. Each represents the same color identity in
both themes, but uses a bright dark-mode variant and a deeper light-mode variant:

| Choice | Dark | Light |
| --- | --- | --- |
| Electric blue | #32C5FF | #0077BF |
| Coral | #FF758F | #BD254F |
| Jade | #3EE6C5 | #007C70 |
| Amethyst | #BA91FF | #7740C5 |
| Amber | #FFCB66 | #A56100 |
| Orchid | #FF7BD5 | #B51A8B |
| Leaf | #79D878 | #367222 |
| Iris | #91A9FF | #435BC0 |

**Individual tank:** in the room roster, click the small color swatch beside the
participant's team selector. Choose a palette color or **Team / default** to
inherit its numbered team's color, or its default seat color in Free-for-all.
This works for humans, bots, and local Player 2. It changes appearance, not team
membership or who can damage whom.

**Team:** open **RULES & MODE → TEAM NAMES & COLORS**. Choose the color beneath each
of the four team names and press **APPLY RULES**. Tanks set to Team/default follow
that choice. A tank-specific override takes precedence. Numbered team labels
remain available to distinguish allies even when their paint is different.

Only the current private-room host can edit these choices, in the lobby or after
completion. Guests/spectators can see them but cannot submit changes. Active-game
edits and invalid/stale palette requests are rejected by Go. Matchmaking battles
retain their locked settings rather than allowing a participant to recolor rivals.

Colors are included in shared rooms, accepted roster updates, reconnect state,
saved presets and final participant statistics. A light-mode spectator sees the
light variant of the same choice that a dark-mode player sees brightly. They do
not independently change the host's selection. Existing presets without colors
use defaults; explicit existing weapon lists remain intact.

## Compatibility and installation

The internal pickup IDs **rapid** and **scatter** are retained for old presets
and rule selections, but are displayed as Machine gun and Shotgun everywhere in
the playable UI. This release changes their gameplay intentionally. There are
still ten pickup types; other weapons, score conditions, teams, objectives,
matchmaking, chat and spectator roles remain included.

Stop the old server, preserve custom deployment configuration, and replace
**all Go sources and the complete web/ folder**, including the new `arsenal.go`
and `colors.go`:

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. Both `/healthz` and `leqra.version` should
report **4.4.0**. **Do not mix old clients and the new server**: older browsers
cannot decode the compact Machine gun samples or display stacked shields/colors.
A compiled deployment must rebuild because it embeds the browser assets:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can use
`docker compose up --build -d`, preserving their settings. Restarting removes
in-memory rooms, queues, scores, chat, and reports. Browser-saved presets, controls,
theme choices and other preferences remain where storage is available. No new
game runtime modules, database, accounts or npm build step are introduced. This
is source for the running server, not a newly hosted public service.

## Verification

**Passed:** 444 top-level Go tests with the race detector (838 including subtests),
65 JavaScript tests, 22 production HTTP/WebSocket assertions, and 234 browser
assertions (193 new gameplay/palette checks plus 41 online firing regressions).
Two opt-in fixture/generator Go tests were skipped, not counted as passes.
Go vet, script syntax, a compiled build, and embedded-asset byte checks passed.

Tests cover exact speed/size, shooter immunity, shield hits/expiry/weighting,
continuous streams, compact wire decoding, host authorization, preset/share and
reconnect colors, both local pilots, matching icons, theme changes and stable
phone HUD geometry. The existing online-firing test ran with synthetic 90 ms
one-way delay plus ordered jitter and checked previews, confirmations, remote
detonation, frozen winning cooldowns, and reconnection.

Tests use Chromium desktop/mobile emulation with exact injected assets, synthetic
Location/History/storage adapters, and real local Go sockets. Physical phones,
Safari/Firefox, native deep-link/storage lifecycles, physical audio output, public
hosting, real packet loss, Docker execution, and production load were not tested.
The eight-gun trial is a bounded deterministic stress test, not a latency/FPS
benchmark. See **TEST-NOTES-v4.4.md** and **tests/results/v4.4/** for actual runs.
