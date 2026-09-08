# leqra v4.33.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **573 top-level tests; 1,125 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **299 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed successfully; browser scripts were not executed.
- All nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.33.0**, with only the current asset directory shipped.
- HTTP, immutable asset/cache, version-handshake and theme-entrypoint tests passed in the full Go run after asset synchronization.
- `git diff --check`: passed.

Raw outputs and the native canvas review are in `tests/results/v4.33.0/`. The full regression runs cover the combined final source. One old Godlike test expected the now-removed new-bot dropdown; that obsolete assertion was removed while the setup and individual-roster selection checks remain.

## Survival wave retries

New server and client regressions cover active-wave and lost-wave restarts, repeated retries, boss equipment, wave-one retries, preserved maze/navigation caches, countdown resets, timer resets and removal of stale hazards, effects and inputs.

Statistics restore the start-of-wave checkpoint, preserve earlier completed-wave totals, and keep previously published reports immutable. Participant identity checks cover departed players, spectators, disconnected tanks, replacement seats and all-bot squads. Setup edits invalidate stale checkpoints.

Online checks exercise host authorization, spectating-host control, private-room restrictions, generation/wave guards, stale or duplicate requests, pending confirmation, errors, timeout and reconnect cleanup. Room capability updates are checked through wave/break/loss transitions. Fresh generations close stale menus and allow subsequent loss reports to appear.

## Lobby and menu controls

Add Bot regressions cover all four difficulties, no-bot Normal defaults, roster order after seat reuse, ignoring human/local/spectator entries and queued online difficulty edits. Explicit valid protocol difficulty values remain supported; invalid values are rejected.

Host-row fixtures exercise readable team/difficulty descriptions, human/local/bot labels, room changes, cached status nodes and moderation actions. Source/cascade review covers centered primary labels and decorative arrows, callsign/host-control separation, compact host rows and responsive Rules, Controls, Presets and Results layouts. No tests were added solely to mirror CSS declarations.

## Tank labels and local-player markers

Production drawing regressions cover fixed name positions as effects change, the closer clockwise badge arc, edge handling, desktop/mobile scales, ownership, spectator/bot exclusions, marker expiry, countdown transitions and Survival wave starts.

Native canvas rendering of the actual tank/icon functions was visually reviewed with local Player 1 and Player 2 markers and multiple effects. `badges-canvas.png` is a native canvas review, not a browser screenshot. The expired-marker path returns before roster lookup during ordinary live frames; badge position arrays and icon sprites remain reused.

## Network fixes and optimization

Remote angular extrapolation now respects the current enabled Speed stacks instead of using a fixed one-stack cap. Regression cases cover zero, one, two and five stacks, both turn directions and angle wrapping.

The shot presentation ledger uses direct early-exit pending-shot checks without temporary preview arrays. A synthetic ledger-only comparison (300,000 sync calls, 60 previews, five runs) measured median times of **44.61 to 5.32 ms** with no accepted previews, **55.19 to 35.83 ms** with 40 accepted, and **60.38 to 50.37 ms** with all 60 accepted. These measurements describe the ledger operation, not overall game frame rate.

## Verification limits

Live browser inspection remains unavailable because browser security policy previously blocked local and inline previews in this workspace. No browser screenshots or physical-device tests are claimed. Native select rendering, touch hit areas, small-screen spacing and real-device gameplay appearance still need device verification. Node fixtures execute production logic and state transitions but do not establish native browser rendering; the canvas review covers drawing geometry only.

Historical browser reports and scripts retain their release provenance and were not treated as current runtime verification.
