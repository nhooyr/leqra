# leqra v4.44.0 verification

- Full JavaScript suite: **469 passed**, zero failed or skipped.
- Full `go test -count=1 -json ./...`: **611 top-level tests; 1,247 including subtests passed**, zero failed. The two opt-in fixture generators remain skipped by default. This release run did not use race detection; server behavior is unchanged apart from the application-version update.
- Production `go build -trimpath -o ... ./src` passed with Go 1.23.12.
- Five shipped JavaScript files passed syntax checks; all 69 retained Python files parse.
- Eleven HTML asset references resolve, all six developer/production asset pairs are byte-identical, only the current asset directory ships, and server/browser/PWA/cache versions agree on 4.44.0.
- Root file count remains five, the shell launcher passes syntax validation, and current README/documentation links resolve.
- `git diff --check` passed. Logs are under `../../src/tests/results/v4.44.0/`.

## Invite regression checks

Nine new behavior tests execute the production initialization, join, dialog and welcome handlers with a test DOM/connection recorder. Against baseline 3752794, seven fail and two pass; all nine pass after the change. Evidence is in `invite-before.tap` and `invite-after.tap`.

Coverage: fresh invitations; recent matching sessions; expired, future-dated and unrelated credentials; editing the target room; Back and Escape; Enter submission from callsign; invalid room names; removed-player notices and manual rejoin; spectator confirmation; automatic recovery without an invite; duplicate submission during connection; and applying the confirmed callsign after a resumed welcome, including a network retry. No connection call is made while a valid invite is waiting at the join menu.

## Styling review and limits

Reviewed the source cascade for outlined connection actions and every `.kick-button`/`.kick-confirm` context, including hover, pressed, focus and disabled states. The solid fill override is now limited to PLAY. Chat color and its unread border/badge use the same `var(--info)` token as Spectators. Existing geometry is retained.

These are source and automated function checks. The browser security policy previously blocked the game page and explicitly prohibited alternate capture routes. No native browser/device appearance test or new screenshot was performed. The existing README image is unchanged.
