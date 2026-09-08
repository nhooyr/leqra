# leqra v4.37.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **592 top-level tests; 1,180 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **379 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12. The production build includes the final browser assets.
- All five shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed; browser scripts were not executed.
- Nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production counterparts byte for byte.
- Server, browser, HTML, PWA registration and offline cache use 4.37.0; only the current asset directory is shipped.
- `git diff --check`: passed.

Raw logs are under `tests/results/v4.37.0/`.

## Roster controls and online setup

Local P2 regressions execute queue-status and queue-cancelled handlers, then invoke the actual Remove button callback. Cancellation restores the button immediately, and repeated unchanged metadata preserves its usability. A deliberately stale disabled button is repaired without replacing its cached row. Cancelling a confirmation cannot unlock queued, matched, away, disconnected, non-host or active-local controls.

The same queue-entry and cancellation sequence covers cached local and human spectator rows in both spectator lists. Buttons lock and unlock without replacing rows. The reported queue cancellation failure and the related spectator failure were both reproduced before their fixes.

Rules/Presets checks use the WebSocket message callback. They cover unrelated broadcasts, partial rule matches, identical rule submissions, complete preset roster confirmation with a host in a nonzero seat, duplicate Apply, connection/host/room changes, send failure, rejection, timeout and stale callbacks. Invalid inherited object names are rejected in bot difficulty and power-up selections before local or online mutation.

## Results and Survival countdown

Client and server tests preserve departed participant scores in all four modes, including seat replacement, returning members and Survival wave checkpoints/retries. Completed reports retain their existing frozen-result behavior.

Canvas draw fixtures keep CTF flags/bases and the Hill objective in the final compact preview, compare their draw calls with the live scene, and verify rendering does not mutate the captured state. Local and online paths are covered.

Survival HUD tests assert that the pre-boss hold contains only the cleared wave. The following countdown starts at three seconds, displays the scheduled boss and enabled equipment, and removes that information when combat begins. Local pause/resume and online authoritative rule changes, including disabled equipment, are covered. Existing two-second result and three-second round-flow boundary regressions remain in the passing suite.

## Performance and layout

New Go tests preserve independent member snapshots, deterministic spectator order and host election, expiration cleanup (including local P2), empty rooms and traversal across rooms. Benchmark results and allocation counts are documented in `PERFORMANCE-v4.37.0.md`; they are operation-level measurements, not gameplay FPS claims.

The room controls received source and structure checks: Unshare/Leave are before Copy Invite, Join another room remains a text button before the dynamically inserted matchmaking launcher, and the connection actions use equal grid columns with a single-action fallback. These are not live rendering checks.

## Verification limits

The browser preview is blocked by the workspace browser security policy (`ERR_BLOCKED_BY_CLIENT`). No live browser or physical-device verification is claimed. Native Safari appearance, narrow-screen button layout and final paint behavior still need a device check. Historical screenshots and browser reports retained in the project are not current-release visual evidence.
