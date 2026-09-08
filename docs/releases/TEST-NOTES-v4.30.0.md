# leqra v4.30.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **557 top-level tests; 1,077 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **253 passed; 0 failed**.
- The final **EXPIRES** microcopy adjustment passed all six weapon HUD regressions afterward.
- `go vet ./...` and the production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed syntax checks.
- All nine HTML asset references resolve. Root JavaScript, CSS and SVG sources match their versioned production copies byte for byte.
- Server, client, HTML, PWA registration and service-worker cache use **4.30.0**, with only the current versioned asset directory shipped.
- Final HTTP, asset/cache, version-handshake and theme-entrypoint checks passed after asset synchronization.
- Retained Python browser scripts passed syntax checks; they were not run against a browser.
- `git diff --check`: passed.

The Go race run covers the final server source. The last client-only wording adjustment is covered by the focused weapon run and final build/asset checks. Raw results are in `tests/results/v4.30.0/`.

## Boss preview

Six client regressions cover equipment and rotation, disabled pickups and filtered weapon choices, ordinary waves, final-wave targets, pause/resume, wave starts, and authoritative online state. Sixteen shared fixtures are checked against the actual Go boss equipment grants and the client wave plan so the preview cannot silently describe a different loadout.

Local boss spawning consumes the same Shield/Speed/weapon plan used by its preview. The four-second break is unchanged. No protocol fields were added.

## Lineup

Eight regressions cover one escaped row per team member, all four AI strength labels, individual elimination state, Godlike boss identification, local and online enemy waves, reused enemy seats, empty intermission snapshots, fresh runs and lobby cleanup. Enemy groups do not receive fabricated scores, score pips or mini-scores.

The roster cache includes individual member state and the score target. Idle renders skip document writes, while deaths, difficulty edits, renamed tanks and wave changes refresh the appropriate display.

## Machine-gun readout

Six weapon HUD regressions cover independent P1/P2 values, pauses, ammo waits, expiry/replacement, online predicted shots, and unforced live updates driven by actual local shots. Values round upward to tenths so a remaining shot does not display as zero seconds. The depletion bar uses the remaining round count against the 180-round total.

The firing budget replaces the machine gun's projectile-slot dots within the existing 28-pixel ammo slot. Hidden slot counting, document rebuilding and ARIA writes are skipped; switching back to another weapon restores the correct slot display. The separate equipment deadline reads **EXPIRES** to distinguish it from **FIRE LEFT**.

Existing server and client firing-budget regressions remain enabled, including idle/blocked budget preservation, normal equip expiry and a maximum of 180 successful rapid shots.

## Rename and summary layout

Survival wording was updated throughout current production labels, validation messages and the built-in preset. The internal mode ID and user-named saved presets remain unchanged. Existing mode/rules tests pass with the new label.

Summary items keep their nonwrapping text. Separators are positioned in the gap before an item; the summary clips a separator when that item begins a wrapped row. This avoids layout measurements, resize handlers or per-frame work.

## Verification limits

Live browser inspection remains unavailable because the browser security policy previously blocked local and inline previews in this workspace. No browser screenshots or physical-device tests are claimed. Native wrapping, the new timer's mobile readability and the boss preview's narrow-screen appearance still need device verification. Node fixtures exercise production logic and event/state transitions but do not establish native browser rendering. Historical browser reports and screenshots retain their original release provenance.
