# leqra v4.23.1 test notes

## Requested regressions

The focused v4.23 browser suite passes **18/18** checks. New assertions verify:

- **Leave match** is visible in an online pause menu;
- after actually leaving that online match and returning to local play, **Leave match** is hidden;
- local **PLAY AGAIN** computes to the same neon-green `rgb(57, 255, 136)` background used by matchmaking REMATCH;
- a server shutdown returns the client to local Home state and opens the pronounced **SERVER SHUTTING DOWN** modal;
- no uncaught browser error occurs through those transitions.

The retained v4.23 checks in the same run also cover zero startup WebSockets, version mismatch handling, the v4.23.1 version handshake, team balancing, explicit online connection, maze preservation on Unshare, and chat-focus input behavior.

## Broader verification

- `go test -race -count=1 ./...` — passed.
- `node --test tests/*.test.cjs` — **57/57 passed**.
- `go vet ./...` — passed.
- `go build -trimpath` — passed.
- `node --check web/assets/v4.23.1/game.js` — passed.
- `node --check web/assets/v4.23.1/pwa.js` — passed.

The focused browser harness uses Chromium with exact shipped HTML/CSS/JS injected into a controlled page while its online gameplay connection uses the real loopback Go fixture. It does not substitute for physical iPhone/Android/Safari acceptance testing.
