# leqra v4.5 — dark-only, authoritative team paint, and stacked Speed

## 1. Light mode is removed

leqra now has one appearance: the dark neon-blue interface. The old Auto / Light /
Dark preference, `prefers-color-scheme` listener, theme storage value, light palette,
and light-only Canvas paints are removed from the playable client. There is no
appearance selector in Settings & Controls.

The remaining `theme.js` / `theme.css` files are dark-only palette infrastructure;
they centralize the neon-blue UI accent and the eight curated tank/team colors rather
than implementing multiple themes. Changing room/game state does not do runtime
appearance negotiation or trigger palette-driven arena redraws.

## 2. Team color is authoritative in team games

When **Teams** is selected, every tank on a numbered team uses exactly that team's
host-selected color. There is no individual tank-color control in the roster and a
saved Free-for-all paint cannot override the team color.

The host can still edit the four team colors under **RULES & MODE → TEAM NAMES &
COLORS**. The eight available colors are:

- Electric blue
- Coral
- Jade
- Amethyst
- Amber
- Orchid
- Leaf
- Iris

The Go server enforces the rule. Individual paint requests during a team game are
rejected; old per-tank FFA paint is cleared when the room enters Teams. Team-room
broadcasts also omit per-tank color metadata that has no effect.

## 3. Free-for-all tank colors are owner-controlled

Free-for-all keeps individual tank colors. Permissions now match ownership rather than
host status:

- An online human can edit **their own** FFA tank color between matches.
- A controller can edit its attached **local Player 2** color.
- The private-room host can edit **bots**.
- The host **cannot repaint another online human**.
- `configure` cannot be used to bypass the owner-aware paint action.

A player's accepted FFA color follows that participant through room updates and
reconnects. Public team matchmaking copies deliberately discard private FFA paint,
while the original private lobby keeps it for the player's return.

## 4. Arena labels use callsigns, not slot/team shorthand

With Local Player 2 active, the labels above both locally controlled tanks use the
actual callsigns (for example **ALPHA** and **BRAVO**) instead of replacing them with
P1 / P2.

In team games, the arena label no longer appends T1 / T2 / T3 / T4. Team membership is
shown by the authoritative tank color. P1/P2 still appear where useful as control-slot
labels in menus/HUDs; they no longer replace the pilot callsign above the tank.

## 5. Super Speed stacks to five

Each Speed pickup now adds one stack, up to five. All stacks share one six-second timer;
collecting another Speed refreshes that timer, including when already at five stacks.
The stacks expire together and reset on a new life.

Each stack adds:

- **+65% base movement speed**
- **+25% base turning rate**

So five stacks produce **4.25× base movement speed** and **2.25× base turning rate**.
Ghost remains compatible with Speed; phasing does not remove the stack. The named HUD
shows `SPD×N`, and additional speed streaks are drawn for higher stacks.

The Go simulation, local simulation, online input prediction, bot movement and replay
all use the same stack count and timer. High-speed wall-contact regressions are included
to prevent tunneling through solid walls.

## 6. Speed and Shield have 3× pickup weight

Both **Speed** and **Shield** now have spawn weight **3**. Every other enabled pickup has
weight **1**. With all ten types enabled, the selection pool has total weight 14:

- Shield: **3/14 ≈ 21.43%**
- Speed: **3/14 ≈ 21.43%**
- Each of the other eight types: **1/14 ≈ 7.14%**

Disabling a pickup removes its weight entirely. Starting pickups and later timed spawns
use the same weighted chooser. Map-scaled pickup caps, starting counts, Super fast
1–2-second spawn timing, safe placement and 19-second expiry are unchanged.

## 7. Bugs found and fixed during the audit

The audit found two subtle color-state problems in addition to the requested permission
changes:

1. **Hidden FFA paint could survive a switch to Teams.** It was visually ignored while
   Teams was active, but could reappear later when the room switched back to FFA. Team
   format now clears the individual override at the authoritative room state.
2. **Team matchmaking copies could carry private FFA paint metadata.** The battle color
   was already team-controlled, but the unused personal override could follow the copied
   participant. Team queue copies now remove that metadata while leaving the player's
   original private-lobby preference untouched.

The existing score/death, shields, friendly fire, self-damage, objective scoring,
sudden death, spectators, swaps and post-match-statistics suites were rerun under the
race detector. No new scoring/death defect was found in this pass.

## 8. Optimization cleanup

This release removes work that no longer has a purpose and trims several AI/client hot
paths without changing the 60 Hz server simulation, 30 Hz snapshots, or movement
balance:

- Removed runtime light/dark preference listening, theme-storage synchronization and
  the second palette from the client.
- Local bot target selection now scans once for the best opponent instead of allocating,
  filtering and sorting a temporary tank array.
- Scaled bot tuning is cached by difficulty + Speed-stack count instead of cloning the
  tuning object each bot tick while boosted.
- A small temporary point object in projectile-risk ally checks was removed.
- Cached tank-hull drawing no longer clones tank objects just to substitute paint.
- Team-room broadcasts omit unused individual `colorIndex` data.
- Cosmetic FFA paint changes do not clear unrelated guest ready state.

These changes provide headroom, especially with eight tanks/bots, but this release does
not claim a universal FPS or latency increase. Network quality, browser scheduling,
projectile count and GPU/device limits still matter.

## Install / upgrade

Stop the old server, preserve custom deployment configuration, and replace **all Go
source files and the complete `web/` directory** with this package.

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. `/healthz` and `leqra.version` should report
**4.5.0**. Do not mix older clients with this server: older clients have different color
permissions, Speed semantics, and appearance state.

Compiled deployments must rebuild because browser assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild with
`docker compose up --build -d`. Restarting clears in-memory rooms, matchmaking,
current scores, chat and reports. Browser-saved controls, presets and non-theme display
preferences remain where storage is available. Old theme preference data, if any, is
simply unused.

## Verification

Final verification for this package is recorded in **TEST-NOTES-v4.5.md** and
`tests/results/v4.5/`. It includes the full Go race suite, JavaScript movement/combat
units, a production WebSocket permission test, focused Chromium room/game tests, syntax,
Go vet, compiled build and embedded-asset comparisons.
