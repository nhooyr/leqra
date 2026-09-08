# leqra v3.6 — clear flags, four named teams, scoring fixes and drawing caches

## Capture the Flag: tanks above flags; safe spawns

Flags, their backing cards, tethers and status labels are now drawn **before all
tanks**. Allied tanks cannot disappear underneath their own oversized flag icon.
The flag remains large and readable when unobstructed, with a visible team number
and name. Carried flags still track their carrier; they no longer paint over a
tank that overlaps the marker. This is painter's ordering in the existing 2D
renderer, equivalent to moving flags behind tanks on the Z axis.

The home cell of a tank's own flag is excluded from its starting and respawning
positions, even while that flag is being carried elsewhere. The actual current
position of a friendly flag (including a dropped flag) is also excluded with a
clearance margin. Placement searches reachable nearby cells and prefers space
away from tanks and projectiles. It no longer falls back to the flag's home cell
when its first candidate is unsuitable. A defensive no-valid-cell case retries
rather than placing a tank on its flag.

This applies to humans, bots, secondary local pilots and all eight tank slots,
in the local browser simulation and on the Go server. Players can still drive
onto a flag/base to return or capture it; flags are not new solid obstacles.

## Exactly four teams, or room-wide Free-for-all

**Teams** mode offers only Team 1, Team 2, Team 3 and Team 4. The per-seat
**Independent** choice is removed. Server validation rejects a forged independent
assignment or bot addition in Teams mode, not merely hiding a dropdown option.

**Free-for-all** is still a separate host-controlled battle format. Every tank
is its own opponent, including all newly added bots/local humans and online
entrants. Team selectors are locked in that format. The internal numeric value
zero represents that format's individual sides; it is not a fifth team.

Changing back to Teams places the host and their local P2 on Team 1, with other
participants on Team 2, ready for the host to reassign. Old saved Teams presets
that contain Independent seats migrate those seats into the numbered teams in
the same way. Existing valid numbered assignments are retained when loading a
Teams preset. Existing explicit Free-for-all presets stay Free-for-all.

Capture the Flag still requires exactly **two** of the four numbered teams.
Elimination and King of the Hill support four-team play or room-wide Free-for-all.

## Custom names for all four teams

Open **RULES & MODE → TEAM NAMES**. The host can name each of the four teams,
then press **APPLY RULES**. Examples: Aurora, Red Foxes, Tidal Guard, Violet Squad.

Names support **1–24 Unicode code points**, including spaces, punctuation and
emoji. Outer whitespace is trimmed. Empty/invisible-only names, control characters,
line breaks and oversized names are rejected. Names are rendered as plain text,
never interpreted as HTML. A team keeps its numeric identity and color when it
is renamed; sharing a name does not merge two teams.

Names appear in the roster, team selectors, scoreboard, objective display, flag
labels, chat team labels, swap choices and winning-team popup. Long objective
labels are abbreviated to fit the arena, while the rules editor retains the
complete name. The label includes a stable team number where space is limited.

Names travel with published rooms and saved presets. Old presets without names
use Team 1–4. FFA keeps the four names saved for later team games without showing
them as FFA alliances. Only the host may change the rules, between matches, and
an accepted change clears online guest readiness as before.

## New default lineup

Opening the game now creates the local room with **you plus Rust, Vapor and Ember**,
all three bots at **Normal**, in **Free-for-all** on the **12×10** map. Each tank
is an opponent. You can start immediately, change teams/rules, add P2 or more bots,
or share this exact setup online. Existing saved presets are not overwritten.

The low-level online join-or-create flow still admits the actual visitor rather
than silently occupying extra seats with bots. Publishing the default local room
is how you share the four-tank setup.

## Scoring/death audit and fixes

The audit found and corrected the following issues:

1. **Objective timer overshoot.** The old simulation could take a full movement,
   collision and scoring step after the remaining time had expired or when only
   a fraction of a step remained. A tied CTF/Hill game could consequently gain
   a late point and finish as a normal win rather than entering sudden death.
   Objective physics now stops exactly at the deadline. A zero-time step resolves
   the existing score first; a fractional final step uses only its remaining time.
2. **Post-result score mutation guard.** Objective point helpers now reject calls
   outside live play and during sudden death. The old low-level helper could
   change scores if called after completion. This is defensive hardening; no
   client-authorized endpoint exists for directly invoking that helper.
3. **FFA bot additions.** The old client assigned a newly added bot Team 2 even
   while the room was Free-for-all. Locally this could group opponents; the server
   could reject the same request as a locked-team edit. New additions consistently
   use the room's actual format in both local and online play.
4. **Exactly stacked local tanks.** A zero-distance overlap was skipped by the local
   separation loop. It now uses deterministic separation, matching Go's existing
   behavior, instead of leaving the tanks superimposed.

Four targeted assertions were reproduced as failing against the original v3.5 Go
sources: post-buzzer CTF capture, extra final Hill time, the post-result helper,
and motion beyond the final fractional deadline. They pass against this build.

Checks also cover single grenade explosions and shield absorption, self-damage,
friendly-fire protection, one shared team point per round (including dead teammates
and seat seven), mutual destruction, spectator roles, high-numbered seats and
objective sudden death. Existing weapons and scoring rules are not intentionally
rebalanced. This is a targeted audit with regressions, **not a claim that all
possible bugs have been eliminated**.

## Rendering: less repeated work, without changing the renderer

Static tank hull/tread artwork is cached in small offscreen Canvas 2D images and
reused. The four tread-animation phases, team/FFA colors and resolution variants
are cached; recoil, turret, shields, speed effects and other dynamic visuals remain
dynamic. Repeated label-width measurements are cached too. Both caches are bounded.
The online renderer also avoids repeated secondary-controller lookup in its tank
loop. Physics, collision geometry, tank speed and network update rates are unchanged;
`web/netcode.js` is byte-for-byte unchanged from v3.5.

The controlled rendering A/B, methodology and limits are in **PERFORMANCE-v3.6.md**.
WebGL is **not added in this build**. It could support a batched sprite/particle
renderer, but requires a proper texture-atlas/batching implementation, context-loss
handling and device testing to establish a benefit. It would not by itself speed
up Go simulation, JavaScript bot planning or network delivery. This update first
removes measured repeated Canvas work rather than promising a universal GPU win.

## Apply the update

Stop the old server, preserve your custom deployment configuration, and replace
**all Go sources and the entire web/ directory**, including the new `teams.go`.

```sh
cd leqra-online
go run .
```

Refresh every player's browser. Both `/healthz` and `leqra.version` report
**3.6.0**. Rebuild a compiled server (`go build -trimpath -o leqra .`) or Docker
image (`docker compose up --build -d`): the executable embeds the browser assets.
Use `leqra.exe` on Windows. Do not mix the old client with this backend.

A restart clears shared rooms, scores and chat. Browser-local presets, key bindings
and display preferences remain where browser storage is available. Old presets
are migrated as described above. This is source for your running server, not a
newly hosted internet service. No new runtime package or npm build step is added.

## Verification

**Passed:** 326 Go tests with the race detector, 24 JavaScript networking tests, 61 production WebSocket checks and 244 browser assertions. Both local players passed the synthetic-delay role-change and reconnection regression.

See **TESTING.md** and the version-labelled reports in `tests/results/` for the
checks actually run. Browser tests use Chromium desktop/mobile emulation, exact
shipped assets injected into pages, synthetic Location/History/storage adapters,
and real loopback Go sockets. Tests do not cover physical phones, Safari/Firefox,
actual address-bar navigation, public hosting, real packet loss or Docker execution.
A synthetic benchmark is not a latency, FPS or production-capacity guarantee.
