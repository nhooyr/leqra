# v4.17.0 — bug fixes and hot-path optimization

- Fix Pickup Rate **Off** still waking the spawn scheduler/RNG even though no pickup could spawn; the scheduler now sleeps indefinitely until a new round/rule set.
- Make authoritative wall/projectile/movement ray queries value-based in simulation hot paths and reuse A* / projectile-threat scratch buffers for bots.
- Remove per-tick side maps from elimination/KOTH checks and compact short-lived server/browser arrays in place.
- Replace the 60 Hz room snapshot map/copy/sort path with reusable typed snapshot buffers while preserving the exact wire payload.
- Reuse local-browser bot pathfinding scratch, KOTH/sudden-death side scans, online ownership/trail sets, and direct shot-preview pruning to reduce GC pressure.
- Add randomized wire-parity, disabled-pickup scheduler, deterministic bot-route, all-map/all-mode browser stress, race-detector, and benchmark regression coverage.

# v4.16.0 — lowercase leqra rebrand

- Renamed the product and visible branding to lowercase **leqra**.
- Renamed the canonical browser API, storage namespace, Go module, binary/Docker examples, server banner, and test environment prefix.
- Added migration from the previous browser-storage namespace so saved player settings survive the rename.
- Kept v4.15 gameplay behavior unchanged.

# v4.15.0 — stable lobby maze, Ultra Wide, and per-pilot status feedback

- Move start controls and pickup explanations into each local pilot's fixed-height ammo/status block; fix online local-P2 pickup feedback.
- Preserve the lobby maze across roster/team/responsive edits; regenerate the preview when Map Size changes.
- Add Ultra Wide 24×14 to browser and Go rules.
- Scale uncollected pickup expiry from maze pickup capacity: Giant 30s, Ultra Wide 45s.
- Rename the pause action to Controls, standardize Spectators/Spectating copy, remove NO TANK ASSIGNED, hide FFA team selectors, and color victory scores by tank/team.
- Stop focus loss from pausing local games while still clearing held input.
- Reduce maze-generation temporary allocations and bound the cached maze-canvas pixel budget.

# v4.13.0 — compact desktop shell

- Normal desktop now uses the same compact app/header geometry as fullscreen.
- The hero banner, footer and desktop status slogan no longer reserve space during normal gameplay.
- Normal desktop uses the full viewport width/height shell, so entering fullscreen causes far less maze resizing and shifting.
- Touch/mobile layout is unchanged.

# v4.12.0 — cleaner underbar, Giant FFA preset, larger power badges

- Removed under-arena fire-key badges and the boot-time duplicate score placeholder.
- Removed the local in-game "Return to room to share online" action.
- Changed the 8-tank FFA preset to Giant 16×14.
- Doubled remote/bot active power-up badge size while retaining cached rendering.

# v4.11.0 — cleaner HUD, FFA presets and active power badges

- Simplified the Shotgun pickup icon to a readable three-way spread.
- Fixed Q / SPACE clipping and removed the offline FIRST TO 5 underbar label.
- Removed New local room from the active local pause menu.
- Added built-in 4-tank Large and 8-tank Huge Free-for-all presets.
- Added cached active-power badges to local bots and remote online tanks.
- Reused badge scratch state to avoid a new per-tank/per-frame allocation.

# v4.10.0 — unified 10-second powers and grenade-ownership avoidance

- Keep the Ghost in-wall warning text without blanking the colored cooldown/ammo bar.
- Standardize every timed power-up effect to 10 seconds.
- Extend uncollected pickup lifetime from 19 to 30 seconds.
- Redraw Shotgun as a horizontal shotgun silhouette.
- Bots avoid their own/enemy grenades, but ignore harmless friendly grenades while friendly fire is off.
- Stop rendering extrapolated online pickups once their authoritative lifetime has expired.
- Remove avoidable grenade-AI allocations and a redundant risk-branch.

# v4.9.0 — grenade-aware bots and quarter-range Machine gun

- Predict nearby grenade-body motion and steer/brake around impact contact without treating the full blast radius as forbidden; apply this basic avoidance to all bot difficulties and friendly grenades.
- Reduce Machine gun travel to one quarter of the maze perimeter, with matching bot/client prediction; reduce the per-tank active cap to 96 and compact eight-tank decode bound to 768 records.
- Show `leqra v4.9.0` in the Controls menu.
- Change the Field Manual wording to “Use Controls menu to change keys.”

# v4.6.0 — long-range Machine gun, Q controls, quick replay, and doubled grenades

- Give Machine gun rounds a total half-perimeter path budget (`width + height`),
  including the hidden muzzle section and all ricochets; make them permanently
  shooter-safe and raise only their defensive bounce ceiling so Giant-map range is not truncated.
- Move Player 1's default Fire key from F to Q in one- and two-local-player setups;
  retain Space as the no-P2 alias and migrate the exact old default binding without overwriting custom maps.
- Add PLAY AGAIN beside Back to Room on completed matches and Restart match to the
  local pause menu, preserving the current roster/rules. Online guests use replay to ready.
- Double grenade fuse to 10 seconds and blast radius to 220 world units; enlarge the
  visual blast while retaining wall occlusion, impact detonation and remote detonation.
- Redraw the Laser pickup as an emitter/beam/flaring endpoint distinct from Shotgun.
- Fix the ordinary 22-bounce safety ceiling incorrectly shortening long-range Machine
  gun rounds; clean stale/unused rapid trail state. Preallocate snapshot slices and
  use constant-time compact-round color encoding; reduce grenade outline raycasts.

# v4.5.0 — dark-only teams, self-owned FFA paint, and stacked speed

- Remove the light theme, Auto/Light/Dark preference state, media/storage listeners,
  and light-only palette branches. Dark mode keeps the neon-blue primary accent.
- Numbered Teams now paint every tank from the host-selected team color. Hidden FFA
  overrides are cleared when entering Teams. Arena labels use callsigns without T1/T2.
- In Free-for-all, an online human can paint only their own tank. The host may paint
  bots and owned local seats, but cannot repaint a different online human.
- Super Speed stacks to five. Each stack adds +65% base movement and +25% base turn
  rate and refreshes the shared six-second timer. Speed joins Shield at spawn weight 3.
- Fix team-matchmaking copies retaining private FFA paint metadata. Paint changes are
  cosmetic and no longer invalidate readiness.
- Reduce hot-path allocations by reusing hull data directly, scanning bot targets without
  filter/sort arrays, caching boosted bot tuning, and dropping unused team-room paint data.

# v4.4.0 — shield stacks, Machine gun, Shotgun, and theme-aware host palettes

- Stack shields to five charges with one ring per charge, shared refreshed ten-second
  timer, charge-aware damage/expiry/reset/snapshots, and 3× enabled-pool spawn weight.
- Rename scatter to Shotgun in UI: 3× normal pellet speed and owner immunity;
  preserve the internal pickup ID and existing volley count/equip timer/cooldown.
- Rename rapid to Machine gun: ⅓ diameter, 3× speed, no weapon cooldown, fixed
  60 Hz emission, bounded 1.5-second rounds and 96 active slots. Throttle cosmetic
  work and encode these rounds in compact numeric snapshots without dropping rounds.
- Switch dark primary to neon blue; pair eight curated host tank/team paints with
  deeper light-theme versions, and remap projectile/effect/objective/guide colors.
- Add host-only roster swatches and team palette selectors, validated by Go;
  preserve colors through presets, sharing, reconnects and frozen match reports.
- Retain immediate firing feedback and stable victory HUD; fix compact mobile buff
  layout so shield/speed/Scope/Ghost all fit without consuming extra arena height.
- Add shield, weapon, wire, palette, permission, and browser regressions; keep
  historical reports version-labelled. No universal FPS or capacity claim.

# v4.3.0 — neon themes and automatic appearance

- Replace the dark interface's lime accent with neon green (#39FF14).
- Add a complete light interface and Canvas palette with neon purple (#A100FF),
  contrasting text, pale maze tiles, readable guides and projectile outlines.
- Default to browser-driven Auto; add saved Dark and Light overrides to Settings.
- Select the theme before styles, follow live media/storage changes, report a
  blocked save, and leave presets, bindings and other device preferences intact.
- Redraw cached map artwork only on effective palette changes; do not reset game
  state, arena geometry, held controls, sockets or prediction.
- Preserve team/power-up identities and the shared ten-icon legend/maze geometry.
- Add unit, responsive browser and same-origin embedded-asset regressions; retain
  the existing online firing/cooldown regression. No physics or netcode rebalance.

# v4.2.0 — online combat presentation and cooldown stability

- Remove competing FIRE/BOOM/countdown writers; freeze completed-round HUD states.
- Add bounded local shot/sound/recoil previews, correlated by server volley/life
  IDs with distinct scatter pellets; no client-authoritative damage or scoring.
- Keep confirmed local shots on an absolute birth clock; remove remote birth
  rewind by admitting projectiles on the buffered shooter timeline.
- Deduplicate predicted firing sounds and laser flashes; preserve grenade press
  semantics and independent Player 2 ownership; lasers bypass cosmetic slot caps.
- Continue remote turning during bounded snapshot gaps, respecting life changes.
- Run online cosmetic work per frame, cache particle drag, skip unchanged styles
  and duplicate forced local inputs; localize impact shake.
- Add baseline bug reproductions, unit/real-socket firing tests, and four viewport
  layouts; preserve historical failed runs rather than retroactively passing them.

# v4.1.0 — Ghost and boundary-ricocheting Cannon

- Cannon diameter and speed are 4× normal (28 / 1128 world units); internal
  walls are pierced and the outer rim reflects, including corners and muzzle hits.
- Ten-second independent Ghost buff stacks with speed, Scope, shields and weapons;
  safe deterministic expiry, bots, online prediction and matching icons included.
- Host bot removal is immediate; human-removal confirmation remains.
- New generated Go/JavaScript movement-parity fixtures and local/live UI tests.
- Test notes retain the synthetic-jitter benchmark failures; no speedup claim.

# v4.0.0 — solo and party matchmaking

- Add six human-only queues: Elimination 1v1/2v2/3v3, CTF/Hill 3v3 and eight-way FFA.
- Choose progressively larger fixed maps, with Giant 16×14 for FFA.
- Host queues up to three real pilots; remote controllers individually consent.
- Keep parties on one side with exact team-size packing and randomized fillers.
- Preserve private lobbies and provide return buttons, including after results.
- Transfer local P2 safely; keep source spectators, chat isolation and watch links.
- Lock matched battle rules/teams and combat admission; no opponent kick powers.
- Add cancellation, stale-ticket/input rejection, handoff/reconnect recovery,
  disconnect cleanup, forfeit resolution and bounded queue/return metadata.
- Leave game physics and core network-smoothing modules unchanged.

# v3.9.0 — Cannon

- Add a three-shot, ten-second Cannon weapon: 3× normal radius/diameter, 3×
  speed, wall-piercing flight and 0.85s cooldown. No wall destruction or splash.
- Keep swept first-tank hits, shields, friendly-fire and authoritative statistics.
- Integrate bots, wall-piercing guides, visual extrapolation, shared pickup/legend
  icons, host weapon selection, presets and two-player HUDs.
- Retain v3.8 map supply and Scope; no movement-smoothing-core changes.

# v3.8.0 — giant maze, area-based supplies and Scope

- Add Giant 16×14; retain the Large 12×10 default.
- Scale pickup caps by round(area / 9.8): 5, 7, 12, 17, 23.
- Seed each new maze with 2, 3, 4, 5, 6 pickups, subject to existing enable/placement rules.
- Add independent ten-second Scope buff, matching reticle icons, an eighth host
  toggle, and separate primary/secondary HUD timers with stable layout.
- Trace owned Scope guides to half the perimeter with a shared distance budget,
  wall reflections, team-aware tank intersections and no gameplay mutations.
- Server owns Scope acquisition/expiry. Preserve current movement prediction.
- Preserve old saved map/weapon selections; update fresh defaults and built-in presets.

# v3.7.2 — warning sound and Super fast pickup defaults

- Missile-lock warning sound defaults on; explicit saved opt-outs and global mute still work.
- Add host-selectable Super fast (1–2s) as the default for new local/shared rooms
  and built-in presets; retain existing frequencies and saved preset choices.
- Use a one-second first live-play spawn delay with the existing two starting
  pickups, weapon filters, five-pickup cap and safe-placement rules.
- Keep the frequency label readable in compact phone settings.
- Remove unused pre-rules pickup-timing constants to avoid stale duplicate defaults.
- No changes to weapons, scoring, post-match statistics, flag drawing or netcode.

# v3.7.1 — CTF flag captions

- Removed captions and their backing strips beneath home, dropped and carried flags.
- Removed base captions; kept base rings, numbered pennants and the objective HUD.
- No changes to simulation, networking, match statistics or other gameplay.

# Changelog

## 3.7.0 — post-match statistics

- Add a participant-based match ledger in Go and local simulation, retaining
  counts across rounds, respawns, reconnects and spectator/seat swaps.
- Distinguish enemy eliminations, deaths, self-destructs and friendly-fire kills;
  track personal flag captures/returns and uncontested Hill time.
- Freeze the final report before publishing match completion. Include the
  winning event, retain earlier participants, and reset only for new matches.
- Send cached, credential-free reports to players and spectators only with
  completed-match snapshots; keep the core live netcode unchanged.
- Add a responsive results table/player cards to the congratulations popup,
  with correct initial focus, a scrollable report and an accessible close action.
- See UPDATE-v3.7.md and TESTING.md.

## 3.6.0 — flags, four named teams and audited scoring

- Paint flags/cards/labels behind all tanks and exclude the allied flag home cell
  and current flag position from CTF starting/respawn candidates.
- Remove Independent seat selection; keep global host-controlled Free-for-all.
  Migrate old zero-valued Teams presets and reject new explicit zero assignments.
- Host-editable four Unicode team names, propagated across room UI, objectives,
  scores, victory, sharing and presets, with plain-text rendering and validation.
- Default local setup: you and three Normal bots in FFA on 12×10.
- Correct FFA add-bot/local requests, exact-overlap local tank separation,
  objective final-tick time overshoot and post-completion score helper mutation.
- Cache static hull/tread artwork and label widths with strict entry limits.
  Keep Canvas2D; do not claim a WebGL renderer or a universal FPS improvement.
- See UPDATE-v3.6.md, PERFORMANCE-v3.6.md and current TESTING.md.

## 3.5.0 — chat, eight tanks, maps and performance

- Room-wide player/spectator chat with server-owned sender identity, rate limits,
  plain-text rendering, 60-message reconnect history and an in-game mobile panel.
- Expand every combat/score/input/roster path to eight tanks; keep 16 separate
  spectator places, four numbered teams and one secondary local keyboard player.
- Make 12×10 Large the default; add 14×12 Huge without overriding saved map choices.
- Optional saved FPS/frame-time overlay and lower-cost Performance graphics.
- Avoid redundant HUD mutations and roster copies; narrow wall queries and tank
  collision checks using static-maze indices, preserving narrow-phase behavior.
- Encode one authoritative snapshot per room broadcast rather than per viewer.
- Bound incoming JSON to 8 KiB to accommodate escaped-Unicode chat and eight-seat
  configuration requests; preserve action/frame limits, ownership and moderation.
- No new runtime dependencies. See UPDATE-v3.5.md, PERFORMANCE-v3.5.md and TESTING.md.

## 3.4.0 — combat clarity and objective sudden death

- Reserve both pilots' loadout/buff/cooldown geometry; stop pickup-triggered maze
  resizing and avoid redundant canvas backing-store reallocations.
- Add host-only friendlyFire rules, default off, shared and saved with presets.
  Correct self-hit handling in every seat, including bots; keep deliberate bot
  and missile targeting enemy-only. Laser shooter immunity remains unchanged.
- Add persistent Hide/Show sidebar control and viewport-focused fullscreen layout.
- Display a once-per-match congratulations modal to every player and spectator.
- Draw large, high-contrast foreground flags with team, carry and drop labels.
- Clamp negative snapshot elapsed time; show GO only for a countdown transition.
- On tied CTF/Hill clocks enter a final-life survival showdown with frozen points,
  no respawns, no late-entry extra lives and team-aware winner determination.
  Repeat simultaneous mutual destruction without choosing by seat ordering.
- Preserve core networking, spectator roles, controls, host tools and weapons.
- See TESTING.md for v3.4 verification and limits; older entries below are history.

---

# v3.1.0 — impact and local-player clarity


## v3.2.0

- P2 default Fire is Space; P1 F, single-local aliases retained. Device-local
  remapping with conflict detection, capture cancellation and default reset.
- Host-owned global Free-for-all rule; locked per-seat teams and backend validation.
- Rules dialog: three match modes, three map sizes, score/time/respawn limits,
  pickup intervals and enabled weapon set. Publish/reconnect retain server rules.
- Capture the Flag and King of the Hill with authoritative scoring, respawns,
  objective-driven bots, pickups, team protection and time-limit win/draw rules.
- Saved custom room presets (12) and five built-in setups. Remote guests and
  credentials excluded; online loading refuses to replace any remote controller.
- Independent missile-lock warnings and optional audio; both pilot cooldown
  status/progress, empty-ammo feedback, mobile ring, objective respawn countdown.
- Life epochs prevent interpolation/reconciliation across respawns. Late objective
  entrants inherit an existing team score and use the configured spawn delay.
- 250 Go race-tested cases (378 with subtests), 24 JavaScript networking tests,
  114 production socket checks and 258 browser assertions passed. See TESTING.md.

- Grenades detonate once on living-tank impact; five-second fuse, remote Fire trigger,
  wall ricochets, launch grace and team/shield protections remain.
- Primary Fire is F; Space aliases it only without a secondary local human. Fullscreen
  remains a button. Both keyboard Fire edges target actual controlled seat IDs.
- Explicit Player 2 callsign editors in room and in-match menu, saved separately;
  server ownership/member validation, readiness and round state preserved.
- Separate named P1/P2 ammo, weapon-charge, grenade-fuse and buff HUD panels.
- Homing turn rate 4.8 rad/s, 10-cell wider seeker, 0.06s lost-lock and 0.04s bounce
  delays. Missile speed and half-perimeter path budget are unchanged.
- Shared legend icon rendering, bouncing laser, room features and netcode retained.

# Changelog

## 3.0.0 — Unified rooms, local co-op, bots and teams

- Open directly into a local room, defaulting to a host against two Normal bots.
- One four-seat roster supports remote humans, one second local keyboard player, and per-bot difficulty.
- Host controls names, Team 1–4 / individual free-for-all, bot difficulty and roster membership.
- Team-aware protection, target selection and scoring; first side to five wins.
- Run shared-room bots authoritatively in Go with route planning, aiming, evasion and power-up use.
- Publish a local roster atomically to a new Go-backed room, preserving names, teams and difficulty.
- Preserve direct invites, arbitrary room names, URL updates, host kicking and reconnect safeguards.
- Independently authenticate, predict and reconcile the second keyboard pilot; preserve its input sequence across mazes.
- Tie dependent keyboard seats to their real controller through disconnect, reconnect, kicking and host handoff.
- Increase homing turn rate to 2.8 rad/s, broaden acquisition and shorten lock delays; retain ricochets and half-perimeter range.
- Add unified room, ownership, team, missile parity and mobile tests; retain the core netcode module unchanged.
- Verification: 191 Go tests with race detection, 22 JS networking tests, 82 live protocol checks,
  143 new browser assertions and the delayed-network two-controller regression passed.


## 2.8.0

- Replace font stand-ins with the same seven Canvas icons used by maze pickups.
- Homing missiles survive and reflect off walls and corners, including muzzle contact.
- Limit total flight to half the maze perimeter; debit barrel travel, turns, bounces and nudges.
- Slower steering, a forward seeker cone and lock/rebound cooldowns make close sideways dodges possible.
- Match Go authority, offline physics, AI threat forecasts and online projectile extrapolation.
- Add exact-range, cover/owner/shield, dodge, pixel-equality, and Go/JavaScript parity checks.
- Preserve bouncing lasers, remote grenades, room features, and player-movement smoothing.

## 2.7.0

- Laser wall/corner ricochets share a total range equal to the current maze's perimeter.
- One bounded beam event transmits every visible segment; owner immunity and shield rules remain unchanged.
- Five-second grenade fuse and owner-only early detonation on a fresh Fire press.
- Short press/release pairs survive tick coalescing; held presses never auto-detonate or repeat a throw.
- Detonation survives last-charge, weapon-change and equip-timer expiry; bots can use it against the player.
- Armed-grenade countdown and BOOM mobile button, using the existing controls.
- Remove the blank/random-room hint beside Join; retain the random room creation behaviour.
- New geometry, ownership, input-lifecycle, and real-socket mobile/browser checks.

## v2.6.0 — Custom rooms, faster pickups, and lasers

- Accept arbitrary single-line room text up to 128 Unicode code points, including
  spaces, punctuation and emoji, while preserving legacy six-character matching.
- Let Create Room use an optional typed name; named create/join preserves any
  existing host and uses the same atomic room-allocation rules.
- Update the address bar after a successful welcome with the encoded invite URL,
  using the same URL builder as Copy Invite and never exposing resume credentials.
- Start every round with two pickups; shorten spawning to a two-second initial
  wait and randomized 2–3.5-second intervals, with up to five uncollected pickups.
- Add a three-charge instant laser to Go online play and JavaScript offline play,
  with wall/first-target stopping, shields, bot immunity, and server-owned damage.
- Add magenta beam effects, icons, charge bars, sounds and non-bouncing aim guide.
- Tag visual events with their maze generation so old beams cannot leak into a
  new map. Preserve the existing movement/prediction module byte-for-byte.
- Fit arbitrary-length room names and host controls on compact phone layouts.
- Add room/laser Go tests, live production room-name checks and 67 browser checks.
  See TESTING.md for the actual test run and its limitations.

## v2.5.0 — Homing missiles, grenades and super speed

- Add three new randomly spawning pickups to online, solo and local play.
- Guided missiles acquire visible opponents with bounded turning and wall impact.
- Fused grenades roll/bounce, slow down, then deal wall-blocked area damage.
- Add an independent six-second speed buff with matched Go/client prediction,
  precise expiration, 1.65× movement and 1.25× steering.
- Keep bot-squad immunity and player-only targeting for all projectile types.
- Add missile/grenade-aware bot shooting and threat forecasts.
- Render rocket exhaust, grenade fuse rings, wall-clipped blast effects, boost
  streaks, special shot counts and concurrent status timers on desktop/mobile.
- Keep online projectile simulation, hit outcomes and boost rules on the server.
- Extend tests and fixture scenarios; copy test data into the Docker build stage.

## v2.4.0 — Join or create a room

- A tokenless join for a missing valid code creates that exact room and assigns
  its first pilot as host. Existing rooms still join normally without replacement.
- Room lookup, allocation, and host assignment are atomic under the hub mutex.
  Concurrent joins elect one host and enforce the four-player and server limits.
- Direct invitations also create missing rooms, including a bounded fresh-join
  fallback for explicit invites carrying a saved session from a deleted room.
  Background-only reconnects never resurrect missing rooms or reuse credentials.
- Add a `created` flag to welcome messages. Clarify the join screen's helper copy.
  Keep matched Join/Create colors and the existing mobile layout.
- Preserve host moderation, callsign editing, local modes, and v2.1 smoothing.
  `game.go`, `web/netcode.js`, and `web/style.css` are unchanged from v2.3.
- Add 14 top-level Go tests and 10 production WebSocket checks; expand browser
  room tests to cover join-or-create, host status, typed codes, stale invites,
  protected background resumes, and restricted browser storage.

## v2.3.0 — Host player controls

- Add host-only Kick buttons in the room roster and live-match menu.
- Confirm the selected callsign using a native modal; Cancel/Escape send no action.
- Authorize every kick on the Go server using live host identity, current room and
  a public seat-incarnation ID, preventing self-kicks and stale-slot removal.
- Remove connected or disconnected pilots, clear controls and owned projectiles,
  eliminate their tanks, notify remaining players and preserve other scores/readiness.
- Revoke the removed session and stop auto-reconnect/invite fallback, including
  recovery when the original removal notice is lost. Keep deliberate rejoin possible.
- Transfer controls with host handoff; fit host controls and actions on small phones.
- Preserve game simulation and movement smoothing modules unchanged from v2.2.
- Add 19 top-level Go tests, 10 production WebSocket checks and 46 browser assertions.

## v2.2.0 — Better room flow

- Add callsign editors in the online room and live-match menu; Save or Enter
  updates everyone without reconnecting, resetting readiness, or changing scores.
- Add socket-authorized `rename` / `renamed` messages, bounded name validation,
  acknowledgement feedback, device persistence, and input-preserving editor sync.
- Auto-join valid invite links using the saved name or PILOT, resuming the existing
  seat when possible; handle full/missing rooms and stale/copied session tokens.
- Match Join to Create Room using the same primary-button color and states.
- Fit the expanded room and match menus on portrait/landscape phone layouts.
- Keep the v2.1 smoothing module and Go gameplay simulation unchanged.
- Add 10 top-level Go tests (18 entries including subtests) and 47 browser checks.

## v2.1.0 — Smooth online movement

- Replay unacknowledged local input using sequence + server-applied held-input ticks.
- Match the Go movement step and keep visual correction offsets out of physics.
- Render sub-tick local movement and sample a continuous remote snapshot timeline.
- Adapt remote buffering to arrival jitter; bounded, wall-constrained extrapolation.
- Increase state snapshots from 20 Hz to 30 Hz while retaining 60 Hz server simulation.
- Coalesce pending noncritical snapshots, preserving reliable world/room messages.
- Catch up a bounded number of server ticks after short scheduler delays.
- Stop rebuilding scoreboard and ammo DOM on every network snapshot.
- Preserve solo squad AI, local duel, rooms, mobile input, and reconnection.
- Add 8 Go tests (including 4 movement-parity subtests), 16 JavaScript tests,
  and an ordered-delay browser benchmark with a test-only straight-line arena.

# Changelog

## 2.8.0

- Replace font stand-ins with the same seven Canvas icons used by maze pickups.
- Homing missiles survive and reflect off walls and corners, including muzzle contact.
- Limit total flight to half the maze perimeter; debit barrel travel, turns, bounces and nudges.
- Slower steering, a forward seeker cone and lock/rebound cooldowns make close sideways dodges possible.
- Match Go authority, offline physics, AI threat forecasts and online projectile extrapolation.
- Add exact-range, cover/owner/shield, dodge, pixel-equality, and Go/JavaScript parity checks.
- Preserve bouncing lasers, remote grenades, room features, and player-movement smoothing.

## 2.0.0 — Go-backed online rooms

- Added 2–4-player human PvP, room codes, invite links, ready checks, host start, and rematches.
- Added authoritative Go maze generation, movement, collision, projectiles, power-ups, round rules, and scoring.
- Added WebSocket snapshots, local movement prediction, remote interpolation, latency display, and a 20-second reconnect seat reservation.
- Added host transfer, late-join spectators, stale-input release, and explicit online menu behavior (matches continue).
- Preserved the v1.1 solo squad AI, bot-only friendly-fire immunity, and local two-player keyboard mode.
- Kept mobile portrait/landscape steering and firing, including simultaneous touch input; added a compact room lobby for short phone screens.
- Packaged embedded web assets, bounded standard-library WebSocket transport, configuration, deployment examples, and automated tests.

The prior single HTML file is replaced by a Go project with `web/index.html`, `web/style.css`, and `web/game.js`. The server embeds these files at build time. Online play requires a running backend; players connect with a browser.
