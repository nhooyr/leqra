# leqra v4.18 test notes

## Release verification

The final release tree passed:

- `go test -race -count=1 -json ./...` — **463 top-level tests passed**, **866 pass events including subtests**, **0 failures**, **2 opt-in skips**.
- `node --test tests/*.test.cjs` — **56/56 passed**.
- `go vet ./...` — passed.
- `node --check web/theme.js` — passed.
- `node --check web/netcode.js` — passed.
- `node --check web/game.js` — passed.
- `go build -trimpath -o leqra .` — passed.

The two skipped Go tests are existing opt-in harnesses rather than failures: the browser-fixture server and the movement-parity harness.

## v4.18 focused browser checks

`tests/polish418_browser.py` passed **9/9** assertions. It verifies:

- Chromium desktop does not show the Chrome recommendation;
- a Safari desktop user-agent does show the dismissible Google Chrome recommendation;
- Giant pickup expiry is **61 seconds** and Ultra Wide is **90 seconds**;
- solo P1 Field Manual movement shows arrow keys above WASD;
- the arena/canvas aspect ratio remains synchronized before, during and after opening Controls through the pause/menu flow;
- simultaneous P1/P2 deaths show **TANK DOWN**, not Spectating;
- a losing local pilot sees **DEFEAT** and no congratulatory copy;
- no uncaught browser error occurs.

The Safari branch was tested by supplying a Safari desktop user-agent to Chromium and removing Chromium's user-agent-data signal. A native Safari/WebKit runtime is not installed here, so this validates the browser-detection/UI branch rather than native Safari rendering.

## Retained browser regressions

The prior release coverage was rerun against v4.18:

- branding/storage migration: **12/12**;
- desktop gameplay/HUD: **16/16**;
- narrow mobile layout/gameplay: **6/6**.

These checks include the fixed-height P1/P2 status HUD, Ultra Wide 24×14, pickup information, results presentation, and the existing leqra storage/API migration behavior.

## Real WebSocket matchmaking

The production-style Go WebSocket browser harness passed **71/71** checks. Relevant v4.18 assertions verify:

- the online in-match menu contains no **BACK TO MY PARTY** action;
- queued-match results expose a neon-green **REMATCH** action to participating pilots;
- spectators do not receive the rematch action;
- a rematch request is not enough until every participating network controller votes;
- unanimous rematch starts a fresh countdown for the same queued matchup while preserving private-party reservations;
- the blue **BACK TO ROOM** action actually transfers each queued player back to the private room reserved for them;
- returning one participant prevents the remaining participant from restarting the old queued matchup around a missing opponent;
- winning pilots receive victory copy and losing pilots receive defeat/results copy;
- no uncaught browser error occurs.

## Server rules and smoke checks

New Go regression coverage checks the authoritative `floor(maximum pickups × 8/3)` ground-pickup expiry rule across every map tier:

| Map | Maximum pickups | Expiry |
| --- | ---: | ---: |
| Compact | 5 | 13 s |
| Standard | 7 | 18 s |
| Large | 12 | 32 s |
| Huge | 17 | 45 s |
| Giant | 23 | 61 s |
| Ultra Wide | 34 | 90 s |

A live compiled-server smoke check confirmed `/healthz` and `/api/config` report **4.18.0**, the served page title is **leqra — Tank Arena**, and the binary starts as `leqra online v4.18.0`.

## Limits

Browser automation uses Chromium and Chromium mobile emulation. Native Safari/WebKit, physical phones, public-host load/capacity, real packet-loss conditions, and every possible browser-extension/zoom combination were not exercised. The pause-menu stretch regression specifically checks that the shipped canvas backing dimensions remain synchronized with the arena's CSS dimensions across the menu/Controls transition.
