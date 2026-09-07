# leqra v4.15 test notes

## Final automated checks

The final source tree passed:

- `go test -race -count=1 -json ./...` — **459 top-level Go tests**, **862 passing
  test/subtest events**, **2 existing opt-in skips**, **0 failures**.
- `node --test tests/*.test.cjs` — **56/56 passed**.
- `go vet ./...` — passed.
- `node --check web/game.js` and `node --check web/netcode.js` — passed.
- `go build -trimpath` — passed.

The existing all-map Cannon/boundary and pickup-density test tables were extended to
include the 24×14 Ultra Wide map, in addition to the new v4.15-specific Go tests.

## Focused Chromium checks

Desktop Chromium at 1365×950 ran **16 assertions** and verified:

- Giant = 23 maximum pickups / 30-second expiry;
- Ultra Wide = 24×14, 7 starting pickups, 34 maximum, 45-second expiry;
- roster name/difficulty/add-P2 edits preserve the exact lobby wall layout;
- team/FFA changes preserve the exact lobby wall layout;
- only a map-size change regenerates the tested lobby maze;
- switching responsive desktop/mobile layout sizes preserves that maze;
- FFA has no per-tank team selectors;
- Controls displays starting/max/expiry information;
- P1 and local P2 get independent ammo-area feedback;
- controls and pickup messages do not change status-area height;
- a P2 Laser pickup updates P2's detail line;
- focus loss does not pause local play;
- the pause action reads `Controls`;
- spectator UI contains no legacy watch-role wording and no `NO TANK ASSIGNED` copy;
- victory score numerals use result-side colors;
- no uncaught browser errors occurred.

A separate 390×844 mobile Chromium run added **6 assertions**: no horizontal page
overflow, arena containment, true 24×14 world dimensions, both local pilot loadouts
available, fixed underbar height after P2 feedback, and no uncaught browser errors.

Representative screenshots are stored under `tests/results/v4.15-browser-final/` and
`tests/results/v4.15-mobile-final/`.

## Limits

Browser checks use headless Chromium desktop/mobile emulation, not physical phones,
Safari, or Firefox. No public-host capacity, real packet-loss, or hardware-GPU benchmark
was performed. The maze-cache and allocation changes are bounded implementation
optimizations, not a claimed universal FPS or server-capacity percentage improvement.
