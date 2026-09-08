# leqra v4.15 — stable lobby maze, Ultra Wide, and per-pilot HUD feedback

## Player-status feedback without moving the arena

The start-of-round control reminder and pickup explanation no longer use the temporary
message area at the top of the maze. Each locally controlled pilot now uses the already
reserved second line inside that pilot's ammunition/status block:

- Player 1 gets Player 1 controls and pickup details.
- Local Player 2 gets an independent Player 2 line when enabled.
- A pickup explanation temporarily takes that pilot's detail line, then the normal
  Shield / Speed / Scope / Ghost status returns.
- The status block keeps the same height whether the line is empty, showing controls,
  showing a pickup explanation, or showing active buffs.

This also fixes an online local-Player-2 bug: pickup events were previously producing
local pickup feedback only for the primary controller.

## Lobby maze stability and Ultra Wide

Editing a local-room roster no longer generates new walls. Names, tank colors, bot
difficulty, adding/removing a pilot, and team-format changes rebuild only the preview
participants and related HUD state. Responsive layout changes also resize the existing
preview instead of generating a different maze.

Changing **Map Size** remains the deliberate lobby regeneration boundary. A new
**Ultra Wide · 24 × 14** option is accepted by both the browser and authoritative Go
rules engine.

Normal round starts still create a fresh maze as before.

## Pickup lifetime scales with maze capacity

Uncollected pickup lifetime is derived from the maximum pickup count for the current
maze using whole-second integer scaling `maximum × 4 / 3`, following the requested Giant
example. The resulting current tiers are:

| Maze | Starting | Maximum | Expiry |
| --- | ---: | ---: | ---: |
| Compact 7×7 | 2 | 5 | 6 s |
| Standard 9×8 | 3 | 7 | 9 s |
| Large 12×10 | 4 | 12 | 16 s |
| Huge 14×12 | 5 | 17 | 22 s |
| Giant 16×14 | 6 | 23 | 30 s |
| Ultra Wide 24×14 | 7 | 34 | 45 s |

The Go server assigns this lifetime authoritatively to spawned pickups and local play
uses the same function. The Controls menu shows the selected maze's starting count,
maximum count, and expiry duration together.

## UI consistency

- The pause-menu action is now simply **Controls**.
- The under-arena spectator caption no longer appends `NO TANK ASSIGNED`.
- Player-facing role language uses **Spectators** and **Spectating**.
- Free-for-all removes per-tank team selectors instead of showing a disabled selector.
- Match-complete score numerals use the tank color in FFA and team color in team modes.
- Losing browser focus clears held input to prevent stuck movement/fire, but it no longer
  changes the game to a paused phase. Local games continue until a player explicitly
  pauses them; online games retain their existing always-running behavior.

## Bug fixes and optimizations

The audit found and fixed the missing local-P2 online pickup feedback noted above. It
also removed two avoidable sources of work:

- local roster/responsive edits no longer regenerate and redraw an unchanged maze;
- browser and Go maze generation reuse a four-entry direction scratch area instead of
  allocating a new candidate slice/array on every depth-first-search step.

The cached static maze backing canvas is also bounded by a pixel budget, with a tighter
budget in Performance graphics mode. This matters most for Ultra Wide and high-DPI
displays while leaving physics, collision geometry, and authoritative rules unchanged.

## Install / upgrade

Replace all Go source files and the complete `web/` directory, then restart:

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. Rebuild compiled/Docker deployments because the web
assets are embedded. `/healthz`, `/api/config`, the Controls menu, and
`leqra.version` report **4.15.0**.
