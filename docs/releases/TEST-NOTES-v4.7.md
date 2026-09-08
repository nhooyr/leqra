# leqra v4.7 — test notes

## Focused persistence regression

Command:

```sh
python3 tests/local_rules47_browser.py --output tests/results/v4.7-local-rules
```

Passed 7 assertions:

1. Applied local rules are written to versioned localStorage.
2. Map, teams, team names/colors and match rules restore in a fresh game instance.
3. Restored Teams settings create a valid default local lineup (host on Team 1, default bots on Team 2).
4. Restored values populate the Rules & Mode controls.
5. Loading a local preset updates the automatically restored current rules.
6. Corrupt stored rules safely fall back to defaults.
7. No uncaught browser errors.

## Regression/build checks

Passed:

```sh
node --check web/game.js
go test ./...
go test -race ./...
go vet ./...
node tests/netcode.test.cjs
go build -trimpath -o /tmp/leqra-v47 .
```

The Node networking suite passed all 30 tests, including five-stack Speed, Ghost,
wall collision, input replay, snapshot buffering and objective respawn interpolation.

## Boundaries

This release intentionally persists rules only. It does not restore live match state,
projectiles, scores, spectators, online sessions, chat or matchmaking state. The
focused browser test uses injected shipped assets and synthetic browser storage;
physical phones, Safari/Firefox and public internet hosting were not exercised for
this rule-persistence-only release.
