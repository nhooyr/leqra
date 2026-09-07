# leqra v4.14 test notes

## Focused Chromium checks

A shipped-asset Chromium test at 1365×950 verified:

- the summary scoreboard is visible while the desktop sidebar is present;
- all eight FFA summary entries render on the same vertical row;
- the score strip does not wrap or grow vertically;
- **F** enters native Chromium fullscreen and **F** exits it again;
- F is rejected as a gameplay rebind and Player 1 Fire remains Q;
- the Elimination pause action is labeled `Restart round`;
- a deliberately nonzero match score survives the restart;
- the round number survives the restart;
- the restarted round begins at the countdown state;
- no uncaught browser errors occurred.

The result is stored under `tests/results/v4.14-browser-final/results.json`.

## Regression/build checks

- `go test -race ./...` — passed after updating the two current-version assertions.
- `node --test tests/*.test.cjs` — **56/56 passed**.
- `go vet ./...` — passed.
- `node --check web/game.js` — passed.
- `go build -trimpath` — passed.

The first race run correctly failed only the two tests that still expected v4.13.0;
those assertions were updated to the new release version and the complete race suite then
passed.

## Limits

Fullscreen behavior was exercised in headless Chromium. Physical-monitor/browser chrome
behavior can differ by platform. No public-host load or real packet-loss benchmark was
performed for this UI-focused release.
