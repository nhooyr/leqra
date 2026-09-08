# leqra v4.28.0 verification

## Final checks

- Full `go test -race -count=1 -json ./...`: **550 top-level tests; 1,006 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **200 passed; 0 failed**.
- `go vet ./...`: passed.
- Production `go build -trimpath`: passed with Go 1.23.12.
- Every shipped JavaScript file passed `node --check`.
- All nine HTML asset references resolve, and root JS/CSS/SVG sources match their production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.28.0**. The package contains only the current versioned asset directory.
- Final HTTP, PWA/cache, version-handshake and theme-entrypoint checks passed after synchronizing the final browser assets.
- `git diff --check`: passed.

The Go race suite covers the final Go source. A subsequent client-only correction to synchronize an open Rules dialog was covered by the final Node run. The production build and asset checks ran after that correction was copied to the production assets.

Raw output is in `tests/results/v4.28.0/`.

## Bot navigation regressions

`bots428_test.go` adds six top-level tests with difficulty and objective subtests. They run real bot movement and objective updates for CTF flag pickup, dropped-flag return, capture at home, hill scoring and wall detours. Every difficulty is exercised. Additional cases cover Godlike collecting a pickup before diverting to combat, holding a scoring hill near a firing opportunity, a reproduced stale-waypoint reversal and maximum Speed stacks.

`tests/bots428.test.cjs` adds nine local-simulation tests. They cover matching objective interactions and scoring, Godlike pickup contact, precise arrival with a nearby ally, retained stand-off distance against enemies, wall detours, consumed shortcut waypoints, full Speed stacks and a bound on route rebuilds during a clear final approach.

Existing Godlike grenade, guided-missile, laser, pickup-selection and co-op initiative checks remain enabled. These regressions verify the identified stopping and backtracking causes; they are not a guarantee that bots can never encounter an awkward maze or combat situation.

## Mode selector and sidebar

`tests/mode428.test.cjs` adds thirteen tests executing the shipped UI/rules functions:

- Mode-specific defaults preserve map, weapons, other rules and participant identities.
- CTF and Survival normalize teams; oversized Survival selections fail without mutation or an online request.
- Native range previews do not apply settings until committed.
- Online selection waits for matching authoritative state and blocks duplicate requests.
- Send failures, server rejection and timeout restore the accepted selection.
- Guests, active matches, matchmaking, disconnected clients and pending settings cannot edit the mode.
- Presets, reconnects and host changes synchronize the selector.
- Unrelated room updates preserve a drag; changed mode, context or edit access cancels stale previews.
- Rules use the selected mode without a second mode dropdown. An open form refreshes after a mode change while unrelated roster updates preserve ordinary draft edits.

Sidebar checks exercised mixed-team bot labels, a difficulty edit before spawning a new tank and online Free-for-all labels. The displayed names match Chill, Normal, Fierce and Godlike in the existing controls. Participant names remain escaped through the existing sidebar renderer.

## Browser scope

Live browser inspection remains unavailable because the browser security policy blocked local and inline previews in this workspace. No new browser screenshots or physical-device run is claimed. UI regressions use controlled Node fixtures and source-level checks; touch rendering and native slider interaction still warrant a device check.

Retained Python browser scripts were migrated from the removed mode dropdown to the home-screen icon choices, including their generic rule helpers. Their syntax was checked, but the scripts were not executed against a browser for this release. Historical screenshots and reports remain associated with their original releases.
