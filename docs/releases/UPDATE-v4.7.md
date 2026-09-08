# leqra v4.7 — automatic local-room rule persistence

## Current rules now survive a reload

The game automatically stores the **currently applied local-room rules** in browser
`localStorage`. A normal reload or a later return to the local room restores those
rules before the room preview is created.

The saved rule set includes:

- game mode: Elimination, Capture the Flag, or King of the Hill
- Teams vs. Free-for-all format
- all four custom team names and team colors
- maze size
- score target
- time limit
- objective respawn delay
- power-up frequency
- enabled/disabled power-up list
- friendly-fire setting

Only **applied** rules are saved. Merely editing fields in the Rules & Mode dialog
and closing it without applying does not replace the stored setup.

Loading a built-in or saved room preset in local play makes that preset's rules the
new current rules, so those settings are restored on the next reload as well.

## What is intentionally not stored by this feature

This automatic record is for **game rules**, not live match/session state. It does
not save current scores, bullets, pickups, tank positions, spectators, online
reconnect credentials, matchmaking state, or chat. Online rooms remain
server-authoritative and do not overwrite your local-room defaults when you join
someone else's room.

The active local roster still starts with the normal default lineup on a fresh
reload. Existing browser-local callsign, Player 2 callsign, key bindings, display
preferences and manually saved room presets continue using their existing storage.

## Safety and compatibility

The storage key is `leqra.roomRules.v1`. Stored data is revalidated using the
same rules validator used by the live game. Missing/older fields are merged with
current defaults before validation, allowing future rule additions to remain
compatible where possible. Malformed, unsupported or corrupt storage is ignored and
the normal default rules are used instead, so bad browser data cannot prevent the
game from starting.

If browser storage is unavailable, the game continues normally for the session; it
simply cannot restore those rules after reload.

## Install

Stop the existing Go server, preserve custom deployment settings, and replace all
Go sources and the complete `web/` folder with this package.

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. `/healthz` and `leqra.version` report
**4.7.0**. Rebuild compiled/Docker deployments because the executable embeds the
browser assets.

## Verification

The focused Chromium regression verifies that a custom 16×14 CTF configuration,
including custom team names/colors, match timers, friendly fire, pickup rate and a
custom power-up subset, is written to storage and restored in a fresh game instance.
It also verifies that loaded preset rules become the new persisted current rules and
that corrupt stored JSON falls back to defaults without a JavaScript error.

The final source also passes `go test -race ./...`, `go vet ./...`, the 30-test
`tests/netcode.test.cjs` suite, JavaScript syntax checking, and a compiled Go build.
Browser testing uses Chromium with a storage adapter because direct browser
navigation is restricted in this environment.
