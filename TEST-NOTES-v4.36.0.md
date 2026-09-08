# leqra v4.36.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **586 top-level tests; 1,160 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **361 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All five shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed; browser scripts were not executed.
- Nine HTML asset references resolve. All six root developer JavaScript/CSS/SVG sources match their versioned production counterparts byte for byte.
- Server, browser, HTML, PWA registration and offline cache use 4.36.0, with only the current asset directory shipped.
- `git diff --check`: passed.

Raw results are under `tests/results/v4.36.0/`.

## Round flow and pickup retention

Client/server boundary tests hold the completed Survival maze for exactly two seconds (240 local ticks or 120 server ticks), then confirm a new maze and generation with a full three-second countdown (360 local ticks or 180 server ticks). The countdown keeps tanks, shields, boss equipment, pickups, the wave timer and accumulated statistics frozen. New wave checkpoints preserve completed progress; retry regressions retain the current maze and discard only the retried attempt's statistics.

Every non-Elimination win/loss or draw shows a compact preview during its existing two-second presentation hold. Local fixtures check the 1,999 ms and 2,000 ms boundaries, and online fixtures cover all modes and outcomes. Existing Elimination checks ensure its completed server hold is not repeated. End/Leave confirmations and delayed room metadata remain respected.

Pickup fixtures check identity, position, age and lifetime during the completed-wave hold and final won/lost scene. Nearly expired online pickups no longer disappear because of render-time extrapolation. New-wave initialization replaces the old pickups.

## Lobby sharing and layout

Publication fixtures cover all four modes with active/spectating hosts and assert one complete initial room and state, including imported settings. Client fixtures follow the share handshake, welcome, authoritative room, repeated generation-zero snapshots and first real maze, with and without local Player 2. Room-code conflict, version refusal and transport failure preserve the local preview and setup. CSS source checks verify the same reserved objective row across modes and responsive Rules footer layout.

## Saved setup and navigation

Thirteen settings regressions cover per-mode rule memory and fresh-page restoration; names, team assignments, bot levels, colors, P2 and spectator restoration; confirmed-host filtering; old storage migration; malformed/denied storage; deduplicated writes; rejected Survival overflow; and staging/applying mode defaults with existing permissions.

Ring drawing tests distinguish primary gold and secondary neon pink, including online seat reassignment and a spectating primary pilot, while retaining protection-based visibility and easing. Navigation checks cover all four BACK TO actions with left-facing arrows and centered text.

## Verification limits

A live preview was attempted through the browser skill. The browser rejected `http://127.0.0.1:8080` with `ERR_BLOCKED_BY_CLIENT`, so no live browser or physical-device visual verification is claimed. In particular, final paint behavior, small-screen spacing and native Safari appearance remain unverified. Current Node fixtures execute production logic; retained historical screenshots and browser reports are not current-release evidence.
