# leqra v4.32.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **559 top-level tests; 1,079 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **273 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed successfully; browser scripts were not executed.
- All nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.32.0**, with only the current asset directory shipped.
- HTTP, immutable asset/cache, version-handshake and theme-entrypoint tests passed in the full Go run after asset synchronization.
- `git diff --check`: passed.

Raw outputs and the native canvas review are in `tests/results/v4.32.0/`. The full regression runs cover the combined final source.

## Dropdowns and centered actions

A source/cascade audit checked the shared closed-select treatment against lobby, roster, Rules, Presets and spectator-swap styles, including responsive padding. The arrow is 12px wide with an 18px right inset and 12px text clearance. Select styles use background color without resetting the shared arrow image. Native focus and selection behavior remain intact.

The invisible color-swatch control explicitly clears inherited arrow padding so its hit area stays inside the compact swatch. Leave Match and its shared game-confirmation action center their text. Existing input, palette and confirmation regressions remain enabled. No new tests were added solely to mirror CSS declarations.

## Stable tank labels

Five production drawing regressions cover stable name position, baseline and dimensions as weapons and every buff are gained, stacked, consumed or expire. They check desktop/mobile scales, maximum shield-ring clearance, clockwise icon ordering, hull/label collisions, maze corners, local/remote/bot/spectator gating, effect expiry and sprite-cache reuse.

Native canvas rendering of the actual tank/icon functions was visually reviewed for no effects, a single weapon, all five effects and edge placement at desktop and mobile scale. The review image is `badges-canvas.png`; it is not a browser screenshot.

Orbit direction vectors are precomputed, and the position arrays and five point objects are reused. Moving tanks do not regenerate icon sprites or allocate new point objects for each badge.

## Survival and HUD

Existing mode-selection/preset tests verify the new 15-wave default while retaining explicit custom targets and unrelated room settings. The staged boss schedule, bot-only squads, intermission lineup retention and end-state shake regressions remain enabled.

Four new HUD regressions fail against v4.31 and pass after the fix. They exercise the production HUD functions through all four modes, local/online status, wave/break/boss transitions, results/lobby transitions, clock boundaries and sudden death. Paused Survival now retains **PAUSED** during both a wave and its intermission.

For 30 unchanged Survival HUD refreshes, the tracked status/round/clock/objective/target text replacements fell from **210 offline / 240 online to zero**. This measures those DOM writes, not overall frame time. Changes in visible values still update normally.

## Verification limits

Live browser inspection remains unavailable because browser security policy previously blocked local and inline previews in this workspace. No browser screenshots or physical-device tests are claimed. Native select rendering, touch hit areas, small-screen spacing and real-device gameplay appearance still need device verification. Node fixtures execute production logic and state transitions but do not establish native browser rendering; the canvas review covers drawing geometry only.

Historical browser reports and scripts retain their release provenance and were not treated as current runtime verification.
