# leqra v4.14 — fullscreen key, persistent summary scores, and round restart

## F toggles fullscreen

Press **F** to enter or leave fullscreen. The header Fullscreen button remains available.
F is now a reserved device shortcut and cannot be assigned to a tank control in the
Controls menu. Existing saved bindings that used F are migrated to a non-conflicting
usable key; the stock pre-Q Player 1 Fire binding migrates to Q. The Field Manual and
Controls help both show the fullscreen shortcut.

Fullscreen is ignored while typing in an input or while a modal binding/dialog flow is
capturing keys, so naming a room or editing a callsign cannot unexpectedly change display
mode.

## Summary scoreboard is always visible and always one line

The compact score strip above the maze now stays active on desktop even while the full
sidebar is visible. Hiding the sidebar no longer changes whether the summary score strip
exists.

For five through eight sides, the strip remains a **single row** rather than switching to
a two-row grid. Each summary entry remains the compact color marker plus score; complete
pilot/team names remain in the sidebar/room roster and accessibility labels. The arena
bar keeps its normal height, so an eight-player FFA does not make the maze jump vertically.

## Local Elimination restart means restart the round

In a paused **local Elimination** game, the old `Restart match` action is now
**Restart round**. It creates a fresh maze/tank/projectile/pickup state and begins a new
countdown for the current round, while preserving:

- every side's current match score;
- the current round number;
- the configured room roster and rules.

The action therefore does not erase a 3–2 match just because the current round needs to
be replayed. Objective modes retain the existing Restart match behavior because they do
not use elimination rounds in the same way.

## Install

Replace all Go source files and the complete `web/` directory, then restart:

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. Rebuild compiled/Docker deployments because the web
assets are embedded. `/healthz`, `/api/config`, the Controls menu, and `leqra.version`
report **4.14.0**.
