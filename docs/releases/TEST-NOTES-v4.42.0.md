# leqra v4.42.0 verification

## Executed release checks

- Full `go test -race -count=1 -json ./...`: **605 top-level tests; 1,239 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **452 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- Five shipped JavaScript files passed syntax checks; all 69 retained Python files parsed.
- Eleven HTML asset references resolve; six root JavaScript/CSS/SVG files match their versioned production copies exactly.
- Server, browser, HTML, PWA registration and offline cache use 4.42.0. Only the current asset directory ships.
- Static DOM and launcher insertion checks confirm one unchanged-ID PLAY control after Join another room, immediately before FIND ONLINE BATTLE. The existing primary styling and local/online start handler are retained. Guest, queue and host visibility rules continue to use that same ID.
- `git diff --check` passed. Raw combined logs are in `tests/results/v4.42.0/`.

## Respawn controls

The new server regression executes real hub input handling and simulation ticks for both CTF and KOTH, with primary and local Player 2 controllers. All four cases failed before the fix: turning stopped on the tick after revival and the acknowledgement changed from sequence 40 to 0.

After the fix, held turns continue without needing another network packet, sequence acknowledgements remain monotonic, an older command is rejected, a fresh release stops the turn and the original input timeout still neutralizes controls. Existing released-tap and held-fire revival checks and projectile regressions also pass with race detection. The local JavaScript simulation already reads current held keys and needs no corresponding change.

## Pilot HUD timing

Four new client behavior tests execute the actual loadout and combat-feedback functions. Three fail on the previous source: expired equipment remains on the HUD, rounded timers remain stale after a refresh, and Survival intermission cooldown/ammo values drift.

The updated checks cover both local pilots during online play, every buff timer, machine-gun budget visibility, fresh server equipment replacing old rendered loadouts, snapshot immutability, frozen intermission/countdown/pause/completed scenes and the resumption of live firing feedback. All 57 related focused tests passed before integration; the full 452-test client suite passes after integration.

The shared equipment helper changes visual copies only. Server equipment remains authoritative; local fire prediction remains limited to active play. Existing snapshot, pickup, protection-ring and laser presentation regressions remain green.

## Chat optimization

All 17 focused chat regressions passed, including four new tests. They verify exact timestamp equality with the prior native Date formatting on the same runtime, one formatter per history batch, message order, channel labels, unchanged ISO dates, fresh live-message formatting, updated device timezone on the next opening, empty history and scrolling to the bottom. Retained tests cover bounded message retention, channel separation, reconnect recovery and draft preservation.

The production history-building functions run in a Node.js v24.19.0 benchmark with native Intl and a lightweight DOM stand-in. Each value is the median of seven samples of 40 renders after warm-up.

| History size | Before | After |
| --- | ---: | ---: |
| 20 messages | 0.9711 ms | 0.1620 ms |
| 120 messages | 6.3950 ms | 0.8430 ms |

The 120-message case is about 7.6× faster in this fixture. It excludes browser layout/paint, networking and simulation, and does not measure game FPS or physical-device speed. Detailed method, reproduction commands and raw results are in `tests/results/v4.42.0/chat-performance.md` and adjacent JSON files.

## Verification limits

No live-browser or physical-device test was performed. Earlier workspace browser previews were blocked by security policy. The PLAY placement was checked through markup, insertion order and existing styles; native mobile appearance and interaction still need a device check. Historical screenshots/browser scripts are not current-release visual evidence.
