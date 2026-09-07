# leqra v3.7 — post-match statistics

## A match report in the congratulations popup

The existing congratulations popup now includes **PLAYER RESULTS** for the whole
match. The winning team/individual, winner names and final side scores remain at
the top. Winning participants are marked **WIN** in the report.

The report covers humans, the named secondary local player, and bots, including
all eight tank slots. It uses the actual participant's name and team, not just
"Player 1" or a reused seat number. On desktop it is a table; on narrow screens
it becomes labeled player cards. The popup scrolls without resizing the maze,
and **BACK TO ROOM** stays accessible at the bottom. It opens at the
congratulations heading, not automatically scrolled to the last row.

### What each statistic means

| Statistic | Meaning |
| --- | --- |
| Eliminations | Enemy tanks personally destroyed with any weapon. Self-destructs and teammate kills do not inflate this number. |
| Deaths | Combat deaths, including your own weapons and friendly fire when enabled. A shield save or spawn-protected hit is not a death. |
| Self-destructs | Deaths caused by your own shells, missiles or grenade explosions. These are also included in Deaths, not extra deaths. |
| Team kills | Teammates personally destroyed. This column appears when friendly fire is enabled or a team kill occurred. It is separate from enemy eliminations. |
| Captures — CTF only | Enemy flags personally delivered to your home base. Only the carrier gets this personal statistic; the normal point is still shared by their team. |
| Returns — CTF only | Dropped friendly flags personally returned. The automatic flag-return timer gives no player a return. |
| Hill time — Hill only | Time alive, out of spawn protection, inside an uncontested friendly hill. Contested time does not count. Multiple allied occupants each earn their own time; this does not multiply the team's score. |

The header shows the game mode and **live match duration**. Elimination also
shows the number of rounds. Duration counts simulation time during live play,
including sudden death; it excludes local pauses, countdowns and round-result
breaks. It is not total wall-clock time since opening the room. Hill time under
one minute displays tenths of a second; longer times use minutes and seconds.

No accuracy percentage or assist count is invented from cosmetic events.
Weapon damage, shared scoring, objectives and win conditions are unchanged.

## Correct across rounds, respawns and role changes

Statistics accumulate through every elimination round, objective respawn and
sudden-death life in the current match. The winning capture and final elimination
are recorded before the result is frozen. Multiple pellets or repeated damage
against the same dead tank cannot award duplicate deaths or eliminations.

The ledger follows **room membership rather than tank-slot number**. Reconnecting,
renaming, or switching to spectating and back keeps a participant's personal
counters. A new participant occupying a vacated seat does not inherit them, even
when the two people use the same callsign. Swapping teams keeps personal totals;
that row is marked **CHANGED TEAMS** and shows the last team played on.

A participant who played and then left, was kicked or switched to spectating
remains in the result as **PLAYED EARLIER**. Leaving a tank is not recorded as a
combat death, and the administrative removal does not give anyone an elimination.
People who only watched do not receive fabricated zero-stat tank rows. Dead
teammates who are still participants share their team's WIN marker.

A finished report is frozen. Later room renames, roster edits, role changes and
network updates cannot rewrite it. Starting a **new match** resets every counter;
starting the next elimination round does not. The result popup still appears
once per completed match and does not reopen on every snapshot.

For exceptionally high membership turnover, each match stores the first **256
combat participants**. If that bound is reached, the report explicitly says later
participants are omitted. This is separate from the existing eight simultaneous
tank slots and 16 spectator places, and does not limit ordinary matches.

## Online authority and performance

Online statistics are recorded by **Go at the actual damage and objective
transitions**. The browser cannot submit eliminations, deaths or captures.
Spectators and late/reconnecting viewers receive the same completed report as
players; it does not depend on seeing every explosion or cosmetic event.

The report is serialized once when the match ends and reused in completed-match
snapshots. It contains public participant information, never reconnect tokens.
**Playing snapshots do not include the ledger**, and the live ammo HUD is not
rebuilt to display it. The new table/cards are built only for the result popup.
The core movement-prediction/interpolation file, `web/netcode.js`, is unchanged
from v3.6. This is not a claim of a measured FPS improvement.

Reports are match/session state, not a permanent career-statistics database.
A server restart clears online rooms and reports. Local reports are not stored
across a page reload. Browser-saved presets, key bindings and display settings
are unchanged.

## Apply the update

Stop the current server, preserve custom deployment settings, and replace **all
Go source files and the entire `web/` folder**, including the new `stats.go`.

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. `/healthz` and `leqra.version`
report **3.7.0**. Both client and server must be updated for online statistics.
A restart resets existing in-memory rooms, scores, chat and reports.

Rebuild compiled deployments because they embed the browser files:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Rebuild an existing Docker Compose deployment
with `docker compose up --build -d`, retaining its custom configuration. No new
runtime dependency, npm step or database is required. This source package updates
your server; it does not deploy a public hosting service.

## Verification

See **TESTING.md** and the version-labelled results under `tests/results/` for
this release's commands, actual checks and limitations. The targeted tests cover
all weapons, shield/invulnerability handling, friendly fire, all eight slots,
winning captures, automatic/manual flag returns, contested hills, respawns,
sudden death, seat reuse, duplicate names, spectators, immutable results and
new-match resets. Browser checks cover 1365×950, 390×844, 320×568 and 844×390.

Browser testing uses Chromium desktop/mobile emulation, exact game assets,
synthetic Location/History/storage adapters and local Go servers. It does not
cover physical phones, Safari/Firefox, actual address-bar navigation, public
internet hosting, Docker execution or hosting capacity. Synthetic network delay
is not a performance guarantee for every device or connection.
