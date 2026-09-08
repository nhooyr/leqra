# leqra v4.34.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **577 top-level tests; 1,131 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **319 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed successfully; browser scripts were not executed.
- All nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.34.0**, with only the current asset directory shipped.
- HTTP, immutable asset/cache, version-handshake and theme-entrypoint tests passed in the full Go run after versioned asset synchronization. The final JavaScript metadata-race correction is covered by the final Node run and production build.
- `git diff --check`: passed.

Raw results and the native canvas review are in `tests/results/v4.34.0/`.

## GO transition and layout

Three new production-function regressions verify that resize callbacks preserve the last canvas bitmap until rendering, repeated unchanged frames do not reallocate it, WebKit one-pixel jitter suppression remains effective, actual viewport changes still apply, and GO initializes the round/HUD before revealing the arena.

Source/cascade review and parsed HTML inspection checked the new stage structure, objective-row insertion, hidden HUD/touch geometry, spectator rows, menu stacking and landscape positioning. Menus retain the full stage area below the arena title while the canvas keeps its playing dimensions. No tests were added solely to mirror CSS declarations.

## Gold rings, labels and power-up icons

Production drawing and online prediction fixtures cover actual spawn-protection expiry, countdown and local pause behavior, independent P1/P2 ownership, spectators and bots, shield-hit grace, online packet gaps, new spawn serials and Survival retries. Gold ends with spawn protection and does not reappear for a shield save.

Labels retain their above-tank position through top-edge movement and power-up changes. Their rendering pass follows maze-clip restoration and reuses the layouts calculated for the tanks. Badge collision checks use visible circle bounds instead of transparent sprite squares, allowing closer placement at the existing readable icon size. Edge handling, effect combinations and sprite-cache reuse remain covered.

The actual drawing functions were rendered and visually reviewed at scales 1.3, 0.5 and 0.2 with top-edge labels, a fully equipped boss and protected/expired local players. `badges-canvas.png` is native canvas output, not a browser screenshot. Labels use existing canvas margins and may be clipped by the canvas boundary when insufficient margin is available; they do not jump below the tank.

## Boss-wave shields and results

Four new Go tests and three local tests cover all boss tiers, humans, local P2, bots, all-bot spectator hosts, disabled pickups, expired or stronger shields, disconnected/spectating tanks, current/lost wave retries, Huge-map duration and clearing equipment before ordinary waves.

Ten new result regressions cover the 500 ms reveal boundary, continued impact effects with frozen simulation/statistics, duplicate terminal snapshots, local and online lifecycle cancellation, new generations, reconnects, room metadata arriving after the final state and opening/closing Controls during the delay. Existing elimination timing is preserved without an additional delay; joining an already-finished online match reveals results immediately.

The lobby summary is checked with configured elimination targets and other modes. Host-row behavior and the wave-retry capability tests remain enabled after the text/style changes.

## Verification limits

Live browser inspection remains unavailable because browser security policy previously blocked local and inline previews in this workspace. No browser screenshots or physical-device tests are claimed. Native select rendering, touch hit areas, small-screen spacing and real-device gameplay appearance still need device verification. Node fixtures execute production logic and state transitions but do not establish native browser rendering; the canvas review covers drawing geometry only.

Historical browser reports and scripts retain their release provenance and were not treated as current runtime verification.
