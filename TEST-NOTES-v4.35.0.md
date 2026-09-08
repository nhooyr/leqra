# leqra v4.35.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **581 top-level tests; 1,141 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **336 passed; 0 failed**.
- `go vet ./...` and production `go build -trimpath`: passed with Go 1.23.12.
- All eight shipped JavaScript files passed syntax checks. All 68 retained Python scripts parsed successfully; browser scripts were not executed.
- All nine HTML asset references resolve. Six root JavaScript/CSS/SVG sources match their versioned production copies byte for byte.
- Server, browser, HTML, PWA registration and service-worker cache use **4.35.0**, with only the current asset directory shipped.
- HTTP, immutable asset/cache, version-handshake and theme-entrypoint tests passed after production asset synchronization.
- `git diff --check`: passed.

Raw results and the native canvas review are in `tests/results/v4.35.0/`.

## Two-second holds

Local and server timing fixtures verify the new two-second Elimination hold and Survival intermission, the final-result delay, preserved start countdown and next-boss preview, and cancellation when the match changes. Boundary checks cover the final simulation tick, including floating-point residue that could otherwise add one frame. Retained intermission integration tests now inspect the still-held state at 1.9 seconds and revival at 2.0 seconds.

Online result presentation uses event ticks to subtract time already held, including skipped round-over snapshots and late terminal packets. Elimination does not add a second hold after the server's round-end timer. Joining an already-completed match remains immediate when there is no active End/Leave decision. Existing finalization tests cover frozen outcomes/statistics with continuing impact effects.

## Online layout and match actions

Three new production HUD/loadout regressions exercise empty lobby snapshots, countdown, playing and End Match, with one or two local pilots. They verify stable panel presence, authoritative equipment before rendered bodies catch up, spectator/P2 combinations and role changes. A separate source/cascade review checked objective, lineup and spectator row reservations and deferred canvas resizing. These checks cover the known source of the online maze resizing; they do not establish browser paint behavior.

Eight new JavaScript regressions exercise callsign blur/autosave followed by the first End/Leave click, round/generation transitions while a confirmation is open, room/socket/member identity changes, private-host restrictions, backpressure, duplicate End suppression, lobby acknowledgement, send failure, server rejection and timeout. End failures remain visible in the menu. Results wait behind valid confirmations and pending End requests, including when the two-second hold has already elapsed; stale confirmations still cancel.

Two new Go tests verify one End command after callsign autosave across playing/round-over/countdown/match-over phases, and one Leave command removing both owned pilots, with exactly one corresponding acknowledgement. The server's existing authorization checks remain enabled.

## Notices and ring fade

Notice fixtures verify both incompatible-version refusal paths, accessible dialog title/message, reload/offline actions, closing stale Join/queue dialogs and preserving the local roster. Survival capacity coverage checks an immediate alert below the mode icons, scrolling/focusing the explanation and sending no rules change when capacity blocks selection. The Elimination rule label is checked as ROUNDS TO WIN.

Protection rendering fixtures cover the shared smoothstep fade over the final 300 ms, zero visibility at expiry, pause/countdown behavior, local ownership, shield-hit grace, online state and existing sprite caching. The actual production ring drawing was rendered and visually reviewed at 300, 150, 75 and 0 ms for local gold and remote grey rings. `rings-canvas.png` is native canvas output, not a browser screenshot.

## Verification limits

Live browser inspection remains unavailable because browser security policy previously blocked local and inline previews in this workspace. No browser screenshots or physical-device tests are claimed. Online start/end paint behavior, notice spacing on small screens, native controls and real-device gameplay appearance still need device verification. Node fixtures execute production logic and state transitions; native canvas output verifies drawing only.

Historical browser reports and scripts retain their release provenance and were not treated as current runtime verification.
