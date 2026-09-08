# leqra v4.39.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **600 top-level tests; 1,230 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **415 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All five shipped JavaScript files passed syntax checks. All 69 retained Python scripts parsed; historical browser scripts were not executed.
- Eleven HTML asset references resolve. Six root JavaScript/CSS/SVG sources match the versioned production copies byte for byte.
- Server, browser, HTML, PWA registration and offline cache use 4.39.0. Only the current asset directory is shipped.
- `git diff --check` passed.

Raw logs are under `tests/results/v4.39.0/`.

## Reproduced collision and presentation defects

Four server muzzle cases failed before the change: nonoverlapping, close grazing tanks were skipped by ordinary shells, missiles, grenades and Cannon. The corresponding five client regression groups also failed before their fix. Tests now exercise immediate impacts, protection and friendly-fire filtering, grenade physical contact, single shield consumption, ammunition/charge accounting, nearest-tank selection, walls before/after contact and Cannon passage through interior walls. Missile range debits reflect actual launch travel. Grenade launch forecasts remain pure and stop at immediate contact.

One retained server Cannon wall fixture contained overlapping tanks; it was reduced to one tank so it continues to test its intended wall-only behavior.

Three online laser presentation regressions failed before the change. A confirmation arriving at 240 or 600 ms now draws its actual path after the old 230 ms preview has expired. Live previews update in place without extending their lifetime. Remote hit/shield events present their same-tick, same-attacker beam first while unrelated shots remain buffered. Repeated snapshot event history and shot sounds stay deduplicated. No client damage or ammunition mutation is introduced.

An additional behavioral regression exercises actual online shotgun preview, rendering and authoritative reconciliation: consumed muzzle-contact pellets remain indexed in the volley but are not drawn moving beyond contact. The later surviving pellet reconciles to its original index and server bullet ID. This test fails on the pre-fix source and passes the integrated release.

Existing direct and ricochet laser checks pass; no server laser intersection defect was demonstrated. Protection, friendly-fire rules and authoritative online positions still determine hits.

## Icons

Eight PNG exports were rendered directly from the existing SVG using Inkscape. Checks decode the shipped PNGs and verify exact dimensions, MIME types, immutable versioned caching, offline inclusion and manifest/HTML declarations. Maskable icons are fully opaque, their artwork stays inside the safe circle, and the former white artifacts are absent. Standard PWA/favicon corners retain transparency; Apple icons use an opaque dark background.

The 1024-pixel regular and maskable exports, Apple export and favicon were visually inspected. The SVG favicon remains resolution-independent and explicitly declares `sizes="any"`. Export reproduction is available through `scripts/render-icons.py`.

## Performance

Five wall-query regressions verify candidate membership/order, bit boundaries, duplicate suppression, corner ties, clearing and cache invalidation across all six maze sizes. **4,050 seeded ray queries** match exhaustive collision results exactly.

The before/after benchmark uses identical seeded Ultrawide queries and reports medians. Complete-query time decreased by 37% for movement, 53% for aiming and 49% for long sweeps. These measurements exclude full simulation, painting and networking. The benchmark's isolated 55-test run predates the final combined suite above. See `PERFORMANCE-v4.39.0.md` and its raw logs for reproduction and practical limits.

## Verification limits

No current live-browser or physical-device gameplay test was performed. The workspace browser preview was previously blocked by its security policy. Installed PWA icon selection/refresh, native Safari appearance, actual latency presentation and phone performance remain unverified. Historical screenshots and browser reports are not current-release visual evidence. Online shots remain server-authoritative; this release does not add lag compensation.
