# leqra v4.41.0 verification

## Executed release checks

- `go test -race -count=1 -json ./...`: **604 top-level tests; 1,234 including subtests**, all passed.
- `node --test --test-reporter=tap tests/*.test.cjs`: **444 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- Five shipped JavaScript files passed syntax checks; all 69 retained Python files parsed.
- Eleven HTML asset references resolve; six root JavaScript/CSS/SVG assets exactly match the versioned copies.
- Server, browser, HTML, PWA registration and offline cache use 4.41.0. Only the current asset directory ships.
- One unchanged-ID PLAY button appears immediately before ROOM NAME / CODE. The dynamic label also remains PLAY. The retained mode suite covers local/online start permissions; results keep PLAY AGAIN.
- The removed volume explanation remains absent. `git diff --check` passed.

Raw combined logs are under `tests/results/v4.41.0/`.

## Badges and online state

Twenty-two focused badge/protection checks passed, including four feature regressions that failed before the badge changes. Tests cover the matching pickup pulse, full opacity outside the expiry window, weapon charges, machine-gun rounds, shield/speed stacks, and fixed offsets through timer/count changes and movement near edges. Cycling all 181 machine-gun counts retains one cached icon sprite.

Actual production drawing functions were rendered with a canvas implementation and inspected for count contrast, corner placement, pulse extremes and reduced mobile scale. The image is `tests/results/v4.41.0/badges-canvas.png`. This is a canvas review, not a live-browser or physical-screen check.

Five additional online integration tests execute the actual receive/render/prediction functions with the production snapshot buffer and predictor. They verify latest-authority equipment, smooth timer aging, refresh and expiry, unchanged source snapshots, freezing of both local predictors during Survival breaks, countdown/result holds, and ricochet rendering/reconnect cleanup. Three timer/prediction regressions failed before the fixes.

## Audio balance and generated-wave headroom

Twenty-six focused audio tests passed. Coverage includes real local wall impacts, online bounce history and cache cleanup, clustered explosion deduplication, shared shield cues, unchanged weapon timbres/timing, saved/default volume and mute, graph reuse, unlock/resume cleanup, and combined native-wave headroom. Multi-layer weapon tests check increasing output at 50%, 75%, 99% and 100%.

The Web Audio ricochet recipe level changes from 0.009 to 0.035; death noise changes from 0.15 to 0.065 and its bass from 0.06 to 0.035. Shared master gain, the existing peak compressor and makeup compensation remain. Native death and layered weapons additionally share a whole-cue gain budget so their overlapping encoded layers do not each approach full scale independently.

Actual native fallback WAVs were decoded as mono signed 16-bit PCM at 22,050 Hz. Layers were summed in floating point with their real offsets, without clipping, browser processing or hardware limiting. The full method and raw values are in `tests/results/v4.41.0/audio-levels.json`.

At the default 50%, the generated death/bounce RMS amplitude ratio narrows from **7.58 to 1.07**. RMS uses each cue's own complete active duration; this is neither total energy nor a perceived-loudness measurement. The old combined native death cue exceeded full scale even though its individual layers did not.

| Individual native cue at 100% | Combined peak after correction |
| --- | ---: |
| Death | 0.718 |
| Laser, local | 0.786 |
| Laser, remote | 0.774 |
| Cannon, local | 0.682 |
| Cannon, remote | 0.667 |
| Pickup | 0.897 |
| Chat | 0.765 |

Peak 1.0 is full scale. These values apply to each complete generated cue, including its overlapping layers. The original unbudgeted local Laser and Cannon peaked at 1.333 and 1.118 in the balanced draft; their shared budgets fix those overruns. Pickup and chat already fit. Arbitrary simultaneous unrelated native media elements can still mix differently in the browser or operating system.

## Server optimization

Four new regressions verify 9,216 exact candidate-set comparisons over all six maze sizes, 6,144 exact ray-result comparisons, bit boundaries/clearing, index invalidation and stable single-cell results. Existing spatial, Laser, Cannon and Ghost regressions passed with race detection.

Five-run medians show complete wall-query time reductions of approximately 6% for short movement, 18% for aiming and 11% for long rays. Both versions use zero steady-state heap allocations per query. Full methodology and raw benchmark logs are linked from `PERFORMANCE-v4.41.0.md`; the figures do not measure total AI time, server throughput or game FPS.

## Limits

No live-browser or physical-device test was performed. Earlier workspace browser previews were blocked by security policy. Mobile layout appearance, native Safari playback, Web Audio compressor transients, hardware output and listening balance remain unverified on devices. Historical browser screenshots and scripts are not current-release evidence.
