# leqra v4.43.0 verification

## Combined release checks

- Full `go test -race -count=1 -json ./...`: **611 top-level tests; 1,247 including subtests passed**, zero failures. The two opt-in fixture generators (`TestBrowserFixture`, `Test41WriteMovementParity`) remain skipped by default.
- Full `node --test --test-reporter=tap src/tests/*.test.cjs`: **460 passed**, zero failed or skipped.
- `go vet ./...` and production `go build -trimpath -o ... ./src`: passed with Go 1.23.12. The final integrated build did not need the worktree-only VCS workaround.
- Executed the production binary and verified `/healthz` reports 4.43.0, the embedded HTML matches `src/web/index.html`, all eleven referenced assets match their packaged bytes and use immutable cache headers, and the service worker retains root scope.
- Five shipped JavaScript files passed syntax checks; all 69 retained Python files parse. Historical browser scripts were not executed.
- Six developer web assets match their versioned production copies exactly; only `src/web/assets/v4.43.0/` ships. Server, browser, HTML, PWA registration and offline cache agree on 4.43.0.
- All source and test bytes were checked across the directory move before version updates. The root has only the requested four files plus `go.mod`; current guide links and root screenshot reference resolve.
- Shell launcher syntax, script imports and icon-export utility passed. Docker paths and Dockerfile-specific ignore placement were checked; Docker runtime and Windows launcher execution were unavailable.
- `git diff --check` passed. Raw combined output and focused evidence are in `../../src/tests/results/v4.43.0/`.

## Maze resizing coverage

Six new checks fail against baseline 15eab8c and pass with the fixes. The 59-check focused set exercises production resize, layout, HUD, spectator, mode/rules, share and lifecycle functions using test fixtures. Its retained checks cover local/online lobby, countdown, play, pause, round holds, results, preview preservation, sharing failure, unshare/disconnect, empty lobby snapshots and deferred canvas allocation. Full-suite checks retain reconnect, mode and selected-map behavior.

The transform regression covers all six configured map dimensions, desktop 1440×900, phone portrait 390×844, landscape 844×390 and near-square landscape 844×590. Pilot → spectator → pilot preserves the scale and offsets for fixed arena bounds. Keyboard tests change visual-viewport height while holding layout-viewport dimensions fixed. HUD tests cover local and online P1/P2 role combinations across seven phases. CSS checks assert retained control/cockpit slots, the spectator banner outside normal flow and removal of side-count height overrides.

These are function, simulation, stub-DOM and CSS-source checks. The arena bounds are fixtures, not browser-computed CSS geometry. They establish regressions for the identified causes; they do not prove every possible resize bug is absent. See `../../src/tests/results/v4.43.0/layout-review.txt` for precise scope and baseline failures.

## Input race and metadata encoding

New server regressions reproduce delayed input in both P1/P2 seat-swap directions: sequence 5001 previously entered the replacement’s channel, could set a fire edge and blocked valid sequence 31. With the fix, stale presses/releases are ignored and the current pilot’s commands work. Two client tests verify the actual packet identities. Existing ownership, spectator, respawn, independent-input and timeout checks pass with race detection.

Four metadata tests compare the typed encoder byte-for-byte with the reference across modes, phases, optional fields, queue/party travel, empty rosters and subsequent member edits. Private tokens remain excluded. Median full-gallery broadcast timing is 105.873 → 15.336 microseconds across five 300-ms runs; allocations are 869 → 7. The raw before/after files and method are in `../../src/tests/results/v4.43.0/room-metadata-performance.md`. This is an isolated operation benchmark, not FPS.

## Native browser and screenshot limits

The Browser tool was initialized and the actual game page was requested. Its URL policy explicitly blocked the page and prohibited alternate routes; none were used. No current native browser screenshot or physical-device verification was possible. The retained README screenshot is a staged production-Canvas render from the previous update, unchanged in this release. Native layout, mobile keyboard/rotation, Safari appearance and PWA installation still need browser/device acceptance testing.
