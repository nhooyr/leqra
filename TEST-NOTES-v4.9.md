# leqra v4.9 test notes

## Focus of this release

The v4.9 checks target four requested changes:

1. bots avoid grenade contact without treating the full blast radius as a no-go zone;
2. Machine gun rounds travel one quarter of the maze perimeter;
3. Controls displays the current game version;
4. the sidebar Field Manual says “Use Controls menu to change keys.”

## Go tests

Command:

```sh
go test -race ./...
```

Final result: **844 passing tests/subtests, 0 failures, 2 existing opt-in skips**.

New focused Go regressions verify:

- exact quarter-perimeter Machine gun range on several map sizes;
- Machine gun shooter immunity is retained;
- active-round capacity can sustain the largest-map full-rate stream;
- repeated ricochets do not make Machine gun rounds outlive their range;
- a Chill bot changes course or brakes when a grenade body is directly in its route;
- a grenade inside the 220-unit blast radius but clearly off-route does not alter the
  bot's movement command;
- a moving grenade crossing the predicted route is treated as a collision hazard;
- the Go build version is 4.9.0.

Grenade avoidance ignores ownership/damage eligibility so a bot also avoids physically
triggering an allied grenade. The avoidance clearance is intentionally far smaller than
the explosion radius.

## JavaScript/networking tests

Command:

```sh
node --test tests/*.test.cjs
```

Final result: **56 passed, 0 failed**.

The Machine gun compact-decoder bound was updated from 1,536 to **768 records**, matching
8 tanks × 96 active rounds. Existing firing prediction, reconciliation, movement,
Ghost/Speed, palette, and remote interpolation checks remain green.

## Focused Chromium browser test

Command:

```sh
python tests/polish49_browser.py --output tests/results/v4.9-polish-browser-final2
```

Final result: **8 assertions passed, no uncaught browser errors**.

It verifies:

- client Machine gun lifetime equals a quarter-perimeter path;
- bot body avoidance steers/brakes for a grenade directly ahead;
- the same bot does not flee a grenade merely because it is inside blast range;
- Controls displays `leqra v4.9.0`;
- the new Field Manual wording is present and the old wording is absent;
- the Machine gun legend describes quarter-perimeter range.

## Static/build checks

Passed:

```sh
go vet ./...
node --check web/game.js
node --check web/netcode.js
go build -trimpath -o leqra .
```

A local built-server smoke check returned `4.9.0` from both `/healthz` and
`/api/config` and still advertised eight tank seats.

## Limitations

Tests use local Go execution and Chromium emulation. Physical mobile devices,
Safari/Firefox, public internet deployment, real packet loss, Docker execution, and
production load/capacity were not exercised for this patch.
