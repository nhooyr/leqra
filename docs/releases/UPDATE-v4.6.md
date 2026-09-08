# leqra v4.6 — Q controls, half-perimeter Machine gun, quick replay, and larger grenades

## 1. Machine gun range and shooter immunity

Machine gun rounds keep their **⅓-normal diameter**, **3× normal speed**, zero weapon
cooldown and 60 Hz maximum emission rate. Their travel is now bounded by one total
path budget equal to:

**maze width + maze height = half the maze perimeter**

The hidden muzzle segment counts toward this budget, just as it does for the game's
long aiming/beam traces. Every wall ricochet consumes the same budget; bouncing never
refills it. The round disappears when the budget is spent or when it damages an eligible
tank first.

Machine gun rounds are now **permanently immune to their sender**. They cannot kill the
shooter or consume the shooter's shields even after bouncing or after the shooter picks
up another weapon. Other tanks still follow friendly-fire, shield and spawn-protection
rules.

The longer range requires more simultaneous rounds at full fire rate on large maps, so
the per-owner Machine gun active-round cap is now **192**. Compact online Machine gun
records remain bounded and the decoder limit is raised to cover eight maximum-range
streams.

### Range-safety bug fixed

The audit found a real bug: the generic ordinary-shell safety ceiling killed any
non-homing round after 22 bounces. On Giant 16×14, a Machine gun round travelling its
requested half-perimeter path can legitimately bounce more than 22 times in a narrow
maze lane. Machine gun now uses the larger defensive ceiling while ordinary shells,
Shotgun and grenades retain their previous safeguards.

## 2. Player 1 Fire is Q

Default keyboard controls are now:

| Setup | Player 1 | Player 2 |
| --- | --- | --- |
| One local human | WASD or arrow alias + **Q or Space** | — |
| Two local humans | **WASD + Q** | **Arrow keys + Space** |
| Mobile primary | Thumbstick + FIRE | Hardware keyboard for P2 |

The exact old stock layout using **F** is migrated to **Q** when loaded from browser
storage. A genuinely custom/remapped control layout is preserved rather than silently
rewritten. The Controls panel and loadout key labels update to Q.

## 3. Quick replay from the win screen

The congratulations popup now has **PLAY AGAIN** beside **BACK TO ROOM**.

- **Local room:** Play Again immediately starts a fresh match with the same roster,
  rules, teams, map, weapons and settings.
- **Online host:** if all connected guests are already ready, Play Again starts the
  next match. Otherwise it returns to the room and waits for them to ready.
- **Online guest:** the button becomes **READY FOR NEXT** and sends that player's ready
  state before returning to the room.
- Matchmaking battles and spectators keep their existing return flows instead of
  receiving a private-room restart shortcut.

Scores and per-match statistics reset because this is a new match; room configuration,
chat membership and spectator roles remain governed by the existing room rules.

## 4. Restart local match from Pause

A local match's pause/room menu now includes **Restart match**. It immediately creates a
fresh match with the room's current configuration. Online matches do not show this
button because one browser cannot unilaterally restart a shared live match.

## 5. Clearer Laser icon

Laser now uses a distinct **emitter → beam → bright terminal flare** icon instead of a
shape that could read like Shotgun's spread. The same shared icon routine still draws
it in the maze, power-up legend and Rules panel.

## 6. Grenade tuning doubled

Grenades retain wall bounces, tank-impact detonation and owner-triggered early
detonation. Their automatic fuse and blast range are both doubled:

- **Fuse:** 5 → **10 seconds**
- **Blast radius:** 110 → **220 world units**

Walls still block blast damage. Shields absorb one eligible blast hit; the thrower can
still be killed by their own grenade. The cosmetic shock ring/burst is enlarged to
match the new gameplay radius.

## 7. Optimization and cleanup

This pass also removes several unnecessary costs without changing movement or scoring:

- Machine gun rounds no longer allocate/update history-trail arrays that their renderer
  never consumes; they use a fixed short speed streak instead.
- Stale rapid-trail entries are explicitly discarded when authoritative compact rounds
  replace another presentation state.
- Server state construction preallocates tank/projectile slices for the current room.
- Compact Machine gun color encoding uses a constant-time canonical-color lookup rather
  than scanning the palette for every round in every snapshot.
- Grenade blast-outline raycasts are reduced while retaining wall-clipped visuals.

These reduce allocations and repeated work but are not presented as a universal FPS or
latency multiplier. Device rendering, projectile count, network jitter and server load
remain independent limits.

## Install / upgrade

Stop the server, preserve custom deployment settings, and replace **all Go source files
and the entire `web/` directory** with this package.

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. `/healthz` and `leqra.version` should report
**4.6.0**. Rebuild compiled deployments because the browser assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild with
`docker compose up --build -d`, retaining their hosting configuration. Restarting clears
in-memory rooms, matchmaking, scores, chat and match reports; browser-saved presets,
controls and display preferences remain where storage is available.

## Verification

See **TEST-NOTES-v4.6.md** and `tests/results/v4.6/` for the current executed checks,
including the full Go race suite, JavaScript networking/combat tests, local Chromium
behavior, retained v4.5 room regressions and a production WebSocket permission pass.
