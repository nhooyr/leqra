# leqra v4.31.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **559 top-level tests; 1,079 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **268 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed syntax checks. All 68 retained Python test scripts parsed successfully; browser scripts were not executed.
- All nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.31.0**, with only the current versioned asset directory shipped.
- Final HTTP, version-handshake, immutable asset/cache and theme-entrypoint checks passed after asset synchronization.
- `git diff --check`: passed.

Raw outputs are in `tests/results/v4.31.0/`. The full regression runs cover the combined source, including the lightweight boss-name HUD helper.

## Survival lifecycle

Production client update tests reproduce a positive impact shake at both lost and won results, then verify it settles to zero without advancing the finished simulation. Pause/menu cases also settle residual shake without advancing gameplay clocks.

Local and authoritative server tests retain the same defeated enemy objects/snapshots through the intermission and replace them with living next-wave bodies. Local lineup entries remain marked as defeated during the break.

Server/local tests cover all-bot start eligibility, a spectating host, human departure, reconnecting at a later wave, bot survival and revival, final wins, empty/unavailable squads, and squad-only frozen reports. Existing readiness, ownership and spectator-seat checks remain enabled.

## Difficulty and equipment

Real local spawn tests cover all 20 waves and enforce boss introductions before each higher regular tier. Server tests cover the staged progression and wave-five integration. Shared Go/JavaScript fixtures check difficulty, boss names, shield/speed counts, weapon rotation and disabled pickup filters against the actual spawn grants.

The preview and objective HUD use the actual Normal/Fierce/Godlike boss name. The HUD uses a lightweight name helper rather than calculating the full equipment plan on every refresh. Existing preview tests still cover intermission countdowns, pause/resume, online state, final targets and stale-preview cleanup.

## Lobby settings

Focused tests exercise format/map changes through the existing authoritative settings flow: successful acknowledgments, unrelated room packets, send failures, server rejection, timeout, reconnect, host/guest permissions and active-match locks. They also verify CTF/Survival fixed Teams, automatic team distribution, preserving the chosen map/format on Rules submission, and maze regeneration only for map changes.

KOTH mode, preset and public catalog defaults are 30, and matchmaking help uses the selected target. Lobby/results label checks preserve literal **START BUTTON** in the lobby and **PLAY AGAIN** on results. Retained Python helpers were migrated away from the removed Rules controls.

## Tank badges

Four production drawing tests cover desktop/mobile scales, multiple simultaneous effects, rotations, bot/remote/local/spectator gating, expiry, sprite-cache reuse and maze-edge placement. Native canvas rendering was visually reviewed at desktop and mobile scale: the icon row sits below the name and clear of the hull.

## Verification limits

Live browser inspection remains unavailable because the browser security policy previously blocked local and inline previews in this workspace. No browser screenshots or physical-device tests are claimed. Native select rendering, lobby spacing on small screens, and real-device gameplay appearance still need device verification. Node fixtures execute production logic and state transitions but do not establish native browser rendering; the canvas review covers drawing geometry only. Historical browser reports and screenshots retain their original release provenance.
