# leqra v4.45.0 verification

- Full JavaScript suite: **476 passed**, zero failed or skipped.
- Full `go test -race -count=1 -json ./...`: **612 top-level tests; 1,250 including subtests passed**, zero failures. Two opt-in fixture generators remain skipped by default.
- Production build passed with Go 1.23.12.
- Independent static checks passed: six source/production asset pairs match byte-for-byte, all eleven HTML asset references and five manifest icon paths resolve, only the current versioned asset directory ships, eight source/shipped JavaScript files pass syntax checks, server/client/PWA/cache versions agree, the shell launcher parses in both sh and bash, and the root contains the requested five files.

Raw results are in [src/tests/results/v4.45.0](../../src/tests/results/v4.45.0/).

## Roster regressions

The focused client group failed five of 42 tests against the baseline and passes all 42 after the changes (`roster-client-before.tap`, `roster-client-after.tap`). Coverage includes adding bots and local P2 into a lower reusable seat in local/online normal and moderation rosters, preserving existing row nodes and unsaved callsigns, keeping the open-seat notice below the tanks, and keeping order through persistence, sharing, unsharing and presets. Wire/simulation seat order is unchanged.

Server regressions failed before the fix and pass with race detection (`roster-server-before.txt`, `roster-server-after.txt`). Add Bot uses the latest bot membership rather than the highest combat seat. Newer local-P2 membership does not change which bot supplies the difficulty; legacy zero-member test fixtures keep a deterministic seat-order fallback.

## Saved-session and removal regressions

Fourteen focused client tests pass (`invite-client-after.txt`). They execute production initialization, join, connection-message and dialog functions with a test DOM/socket, covering fresh invitations, recent matching sessions, unrelated/future/expired credentials, player and spectator recovery, server callsign retention, explicit Enter/JOIN submission, cancellation, duplicate submissions, and active-session retry without allocating another seat.

Rejected `resume_expired` and `room_missing` responses clear the saved credentials and return to JOIN without a fresh connection. Both server kick message forms execute the real kick and leave handlers for players and spectators: credentials are cleared, automatic retries stop, and only a subsequent explicit JOIN sends a token-free request. Reopening an invite with a kick marker also waits for JOIN. The full Go race suite includes the existing actual-server expired-reconnect and kicked-disconnected-seat rejection tests.

## Limits

These are automated behavior, server and source checks. Native browser/device appearance remains unverified: the workspace browser policy blocked the game page and prohibited alternate capture routes. No browser harness or new screenshot was run. The existing README image is unchanged.
