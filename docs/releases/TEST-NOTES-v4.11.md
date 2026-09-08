# leqra v4.11 — test and audit notes

## Focused browser checks

The final focused Chromium harness verifies:

- v4.11.0 browser boot with no uncaught errors;
- 4-tank FFA preset exists and loads 4 tanks on Large 12×10;
- 8-tank FFA preset exists and loads 8 tanks on Huge 14×12;
- single-local-player fire hint is exactly `Q / SPACE`;
- the key badge has no horizontal clipping;
- the offline underbar no longer displays `FIRST TO 5`;
- local pause keeps Restart match but does not expose New local room;
- Shotgun icon reads as one line branching into three right-facing shots;
- a bot with weapon + Shield + Speed + Scope + Ghost produces five badge icons;
- the first four badge centres progress clockwise from top-right;
- no browser JavaScript errors are raised.

Additional layout measurements were made at 320×568, 390×844, 844×390 and 1365×950. At each measured size the Q / SPACE element's scroll width fit within its client width and the document had no horizontal overflow.

## Full regression checks

Final source was checked with:

```sh
go test -race -json ./...
node --test tests/*.test.cjs
go vet ./...
go build -trimpath -o /tmp/leqra-v411 .
python3 tests/polish411_browser.py --output tests/results/v4.11/focused-browser
```

The historical `powerups_browser.py --isolated` helper was also attempted, but that older isolated harness no longer boots the current multi-asset client because it predates the current theme/bootstrap injection path. That harness failure is not counted as a product failure and is not reported as a passing test. The current focused harness uses the exact shipped `theme.js`, `theme.css`, `netcode.js`, `style.css`, `index.html` and `game.js` assets.

## Audit scope and limits

The pass specifically reviewed the new badge state inputs (`power`, `powerTime`, Shield, Speed, Scope and Ghost) in both local tank objects and authoritative online Tank snapshots. Local controlled P1/P2 tanks intentionally omit the badges because their loadout panels already expose the same state.

No server gameplay rules were changed beyond the release version. The complete Go race suite remains the primary regression guard for kills, damage, objectives, room roles and scoring.

Chromium tests are emulated desktop/mobile layouts on the local test machine. They are not physical-phone, Safari/Firefox, public-WAN, real packet-loss, or production-capacity tests.
