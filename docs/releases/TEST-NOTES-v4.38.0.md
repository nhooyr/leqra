# leqra v4.38.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **594 top-level tests; 1,186 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **399 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12. The production build includes the final countdown-tip and HUD assets.
- All five shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed; browser scripts were not executed.
- Nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production counterparts byte for byte.
- Server, browser, HTML, PWA registration and offline cache use 4.38.0, with only the current asset directory shipped.
- The requested shared-room name hint is absent from the HTML. `git diff --check` passed.

Raw logs are under `tests/results/v4.38.0/`.

## Reproduced bugs

Two startup regressions failed before the fix because the browser storage property getter threw `SecurityError` outside the migration function's guard. Tests now cover denied local storage, denied session storage, both denied, independent available-store migration, existing preference preservation and default input/settings initialization.

Two Unshare lifecycle cases failed before the fix: connection loss and leaving retained a pending request and its saved lobby snapshot. Tests execute the actual Unshare, WebSocket close and Leave functions, then retry after reconnecting or joining another room. Old socket callbacks cannot cancel the newer attempt. Existing rejection/send-failure paths remain retryable.

Four server respawn cases failed before the fix: primary and local P2 controllers in CTF and King of the Hill. Each sends an actual fire press and release while dead, then advances the hub through revival. The new life must not fire from that released old-life edge. Another living pilot's quick tap, a fresh post-revival tap, held fire, held turning and sequence acknowledgement remain valid.

## Countdown tips and player rings

Countdown checks cover all four modes, short text, configured score/respawn values, individual enabled power-ups, pickup-off/empty selections, six map sizes, team format, friendly fire and Survival boss-wave thresholds. Tip facts were also reviewed against the actual client and server mechanics.

Lifecycle fixtures execute real round/match starts, Survival next waves, wave retries, replays, local-room recreation and pause/resume. They verify that a countdown keeps one tip while subsequent countdowns advance the selection. Online snapshots retain one tip for the current authoritative generation. CTF and Hill status updates cannot overwrite the chosen tip. Boss countdowns retain equipment-only previews, and cleared-wave holds do not acquire boss details or tips.

Canvas drawing tests check neon-purple P1 and neon-pink P2 rings for local and online ownership, including reassigned seats, a spectating P1 and removed P2. Existing protection expiry, 300 ms easing, pause/countdown freezing and shield-hit immunity checks remain passing. The color change does not alter protection duration.

## HUD performance

Six new regressions compare the consolidated projectile summary with existing ammo, grenade and missile queries. They cover in-place local mutations, authoritative online snapshots, weapon and team changes, friendly fire, removed owners, independent local-player displays, pause/death transitions and projectile read counts.

The deterministic two-pilot scan count falls from ten to four. Benchmarks use identical production HUD functions with a Node DOM stand-in, exclude paint/simulation, and report medians. Details and reproducible commands are in `PERFORMANCE-v4.38.0.md`. The benchmark's isolated test count predates the final combined release suite above.

## Verification limits

No live browser or physical-device rendering test was performed for this release. The workspace browser preview was previously blocked by its security policy. Tip wrapping/readability on small screens, native Safari appearance and actual phone performance remain unverified. Historical screenshots and browser reports in the project are not current-release visual evidence.
