# leqra v4.29.0 verification

## Final checks

- Full `go test -race -count=1 -json ./...`: **556 top-level tests; 1,060 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **236 passed; 0 failed**.
- `go vet ./...`: passed.
- Production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed `node --check`.
- All nine HTML asset references resolve. Root JavaScript/CSS/SVG sources match the production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.29.0**. Only the current versioned asset directory is shipped.
- Final HTTP, PWA/cache, version-handshake and theme-entrypoint checks passed after asset synchronization.
- Retained Python browser scripts passed syntax checks; they were not executed against a browser.
- `git diff --check`: passed.

The full Go race suite covers the final server source. A subsequent client-only reconnect gesture correction is covered by the final Node run, production build and asset checks. Raw outputs are in `tests/results/v4.29.0/`.

## Machine gun and icon

Server and local simulation regressions verify exactly 180 successful rapid shots per pickup, 60 Hz emission, preserved budget while idle or blocked, normal equip expiry, refresh and weapon replacement. Online prediction checks verify independent player budgets and no speculative shot beyond the remaining budget. The older four-second, eight-tank stress fixture now supplies another pickup after exhaustion so it continues to verify projectile and compact-wire bounds.

`tests/weapon429.test.cjs` runs the production HUD and prediction functions. It covers separate P1/P2 readouts, rounding upward to tenths so the last round never displays as zero, pending shots, pauses, ammo waits, death, expiry and replacement. The readout reserves space within the existing status row.

The shared laser icon function was rendered to a raster for inspection at normal size and enlarged scales. This verified the emitter/beam drawing; it was not a browser layout test.

## CTF cooperation and planning cost

Six Go regression functions and seven local JavaScript tests exercise actual bot movement, tank separation and objective scoring. Cases cover all four difficulties; human and bot flag carriers; one and three supporting bots; open and dead-end bases; vacating the capture point; dropped own-flag recovery; maximum Speed; Ghost; cover caching and emergency dodging.

Cover selection examines at most 13 nearby cells plus four home-cell corner positions, then caches its result for 0.4 seconds. The uncached Go benchmark measured **2,841 ns/op, 0 B/op and 0 allocations/op** on this runner. This is a microbenchmark, not a frame-rate measurement. Godlike no longer calculates the ordinary objective plan before replacing it with its own plan.

Cover is tactical, not a hard movement restriction: emergency dodging can briefly cross a carrier's approach. Existing projectile-avoidance behavior remains active.

## Menus and touch

UI fixtures verify fullscreen from the requested dialogs and other menus, nonrepeating F, text/select/remapping/system-key exclusions, and continued protection against gameplay keys leaking through dialogs. Mode-selector tests preserve authoritative online confirmation, rejected-selection rollback and room restrictions while exercising arrow/Home/End radio-group navigation. Whole-item summary markup and selected-button styling are checked at source level.

Touch fixtures run the production event handlers and match-state policy. They verify active/inactive phases, document-level cancelable gesture cancellation, single-finger scrolling, independent joystick + Fire pointers and cleanup, and listener removal outside matches. Reconnect coverage executes the production connection entrypoint: it retains an existing match lock through the temporary menu phase, while fresh/lobby joins and terminal exits remain unlocked.

The policy follows [MDN's touch-action documentation](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action), including the nearest-scroll-container boundary, with cancellation of Safari gesture events as described in [Apple's event-handling guide](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/HandlingEvents/HandlingEvents.html).

## Chat fixes

Thirteen tests cover long open sessions, independent 60-message channel bounds, scroll anchoring above/below evicted rows, following new messages at the bottom, and history replacement. Reconnect checks cover unconfirmed outgoing text, newer drafts, both recipients, hidden panels, persistent warnings and leaving the room. Sending remains disabled while authoritative room details are missing; a temporary reconnect state cannot silently switch an opponent draft to the party recipient. No automatic resend is performed.

## Verification limits

Live browser inspection remains unavailable because the browser security policy blocked local and inline previews in this workspace. No physical Safari/iOS/Android test or new browser screenshot is claimed. Mobile selected-color rendering, native fullscreen and pinch behavior still need a physical-device check. Node event fixtures and source checks do not establish native browser behavior. Historical browser reports and screenshots retain their original release provenance.
