# leqra v4.12 test notes

Focused Chromium assertions verify:

1. `.loadout-key` is absent from the under-arena HUD.
2. The offline underbar score/latency placeholder starts empty.
3. The 8-tank Free-for-all preset loads eight tanks in FFA on **Giant 16×14**.
4. The local in-game menu does not show the old share-return button.
5. Local **Restart match** remains present.
6. A bot with five active effects draws five power badges.
7. Every badge is at least **26 world units** wide/high, double the old 13-unit display size.
8. No uncaught browser error occurs in the focused run.

Additional final checks:

- `go test -race ./...` — passed.
- `node --test tests/*.test.cjs` — 56/56 passed.
- `go vet ./...` — passed.
- `node --check web/game.js` — passed.
- `go build -trimpath` — passed.

Browser testing uses headless Chromium emulation rather than a physical phone.
