# leqra v4.0 — random matchmaking and room parties

## Six queues, one online battle finder

Use **FIND ONLINE BATTLE** in your room, select a queue, and press **FIND MATCH**
for a solo entry or **QUEUE ROOM** for your party. A local room is first shared
with the Go backend automatically; its existing bots and configuration stay in
that private room. File-only offline play cannot enter an online queue.

| Queue | Required real tanks | Map | Win target | Time limit |
| --- | ---: | --- | --- | --- |
| Elimination 1v1 | 2 | Compact 7×7 | 5 round wins | 75 seconds per round |
| Elimination 2v2 | 4 | Large 12×10 | 5 round wins | 75 seconds per round |
| Elimination 3v3 | 6 | Huge 14×12 | 5 round wins | 75 seconds per round |
| Capture the Flag 3v3 | 6 | Huge 14×12 | 3 captures | 180 seconds per match |
| King of the Hill 3v3 | 6 | Huge 14×12 | 60 hill points | 180 seconds per match |
| Eight-player Free-for-all | 8 | Giant 16×14 | 5 round wins | 120 seconds per round |

All queues use the existing nine enabled power-ups, Super fast pickup timing,
map-scaled starting stocks/caps, friendly fire off, and ordinary weapon rules.
Objective games use the normal three-second respawn and tied-score sudden death.
Your private custom rules are not used to change a public match; they are retained
for your return. Teams use fixed Lime Squad / Coral Squad names and colors; FFA
makes every pilot an individual opponent.

Matchmaking selects random compatible opponents and teammates on **this running
Go server**. It does not pool people on other servers or provide a hosted player
population, ranking, skill rating, region selection, or guaranteed wait time.
It waits for the **complete human lineup**; bots never silently fill vacancies.
Once a lineup is formed, everyone moves to its fresh match room and the server
starts a shared **four-second countdown**, with no extra host Start click.

## Queue with your friends

The **private-room host** starts a search for all active real players in that
room. Maximum party size is **three real players**, including a secondary local
keyboard player. Bots do not count and remain in the source room. Spectators do
not count as queue competitors. Make extra people spectators before queueing.

The party must fit one team. A two-person party can enter 2v2 or 3v3; a three-person
party can enter any 3v3 queue. Solo entrants can enter all six queues, including
team games where other solos/parties fill their team. Every party stays together
on **one** team. For example, 3v3 can combine a duo plus a solo against a trio.
Three duos cannot make 3v3 without splitting friends, so that combination waits
for compatible partners instead.

**Eight-player FFA is solo-entry.** A friend party cannot remain an allied team
and also be free-for-all. Likewise, 1v1 accepts one real pilot per entry.

The host's click confirms their own local keyboard pilots. Each remote friend
must press **JOIN THIS SEARCH** in the invitation panel before matching begins.
The panel shows names, confirmation status, the selected mode, elapsed search
time, and aggregate player counts. Unconfirmed people are not added to the
search pool. Invitations expire after two minutes without everyone confirming.

Any participating controller, or the private host, can **CANCEL PARTY SEARCH**.
Closing the panel does not cancel it. Leaving, disconnecting, or changing a
participating role cancels the invitation/search; an unrelated spectator leaving
does not. Starting a different private match, altering rules/roster, or loading
a preset requires cancellation first. A fresh visitor to a queued/reserved room
joins as a spectator rather than silently changing the party.

## Your original room stays intact

The match gets a separate room. Your original room name, bots, rules, teams,
private chat, and participant identities are reserved. People who stayed behind
see **WATCH PARTY'S MATCH**, which opens the normal callsign-confirmed spectator
link in another tab. Private-room chat and match-room chat remain separate.

Both local keyboard pilots travel with their own controller, names, inputs,
ammunition displays, and prediction. P1 can even spectate while controlling an
active P2. Independent local P2s from different source rooms can meet in the same
match without sharing ownership or controls.

Use **BACK TO MY PARTY** in the room, the in-game menu, or the congratulations
popup. It restores your original membership and any attached local player.
Friends return independently; the private setup remains reserved until everyone
has returned or left. A new party search requires fresh remote confirmation.
The original private host remains host; teammates do not lose their private-room
roles because match slots were randomized.

Returning during live play asks for confirmation and forfeits your own tank(s).
It does not award a combat elimination to an opponent. If a side abandons all its
registered tanks, the remaining side wins through the normal final report.
A brief connection failure keeps the ordinary 20-second reconnect grace, rather
than immediately forfeiting solely for a network hiccup. Explicitly leaving or
letting reconnect grace expire releases the original reservation. Closing the
server destroys in-memory matches and reservations as with other room state.

Matchmaking battles have **no player-host**: no former party leader can kick
opponents, change rules or teams, add bots, or restart the match. Private-room
host controls remain available outside a search/reservation. Anyone joining a
public match by link is a spectator, and taking an abandoned combat seat is not
allowed. A matched pilot can spectate or return; re-entering that battle as a new
tank is blocked. Matches do not automatically requeue or backfill vacancies.
Normal room chat, spectators, objective rules, weapons, and post-match statistics
are retained. Unrelated viewers cannot access another person's reserved party.

## Performance and safeguards

Membership, queue consent, team packing, and both room transfers are serialized
by the Go hub. Concurrent arrivals create one assignment, not duplicate tanks or
multiple matches for one ticket. Queue controls validate the current ticket ID,
so an old confirmation cannot approve a replacement invitation. Client input
packets include their current room code to reject controls left over from the
previous room after a transfer.

Search runs at most four times a second, with up to four new matches per pass.
There are at most 256 pending party tickets; the existing room/connection caps
still apply. If the server has no free match-room slot, parties stay queued and
see a capacity message instead of losing their lobby. These are resource limits,
not a tested production hosting-capacity guarantee.

Packing tries the oldest feasible party first, randomizes compatible fillers and
team side, and never breaks party boundaries. The failure case with hundreds of
incompatible duos uses at most three party-size passes rather than repeatedly
solving the same impossible packing. Queue information is not sent with live
movement snapshots, and no matchmaking work is added to the per-frame renderer.
`game.go` and `web/netcode.js` remain byte-for-byte unchanged from v3.9; no tank
speed, weapon, physics, or movement-smoothing rebalance is intended.

Private reconnect credentials never appear in invite links, queue catalogs,
public participant lists, or another client's welcome. Transfers send only the
recipient's own credential. A bounded, short-lived server handoff table also
handles a refresh occurring just before a transfer welcome was received.

## Install

Stop your server and preserve custom deployment configuration. Replace **all Go
sources and the complete `web/` folder**, including the new `matchmaking.go`.

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. The health endpoint and
`leqra.version` should report **4.0.0**. Old clients do not understand queue
consent or transfers; update both ends together.

Rebuild compiled executables because they embed the browser files:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Rebuild existing Docker Compose deployments with
`docker compose up --build -d`, preserving your hosting configuration. No new
runtime module, npm build, account system, or database is needed.

Everyone must open the same server's reachable LAN or public HTTPS address.
`localhost` works only on the server device. This source package does not deploy
an internet service or connect to an existing worldwide matchmaking population.
Restarting clears online rooms, queue tickets, reservations, scores, chat, and
reports; browser-saved controls, presets, and display preferences remain.

## Verification

**Passed:** 402 top-level Go tests with the race detector (786 including subtests),
24 JavaScript networking tests, 127 production HTTP/WebSocket checks, and 114
browser assertions (68 matchmaking checks plus 46 Cannon/mobile regressions).
Go vet, JavaScript syntax checks, a compiled build, and embedded-asset byte checks
also passed. Both local pilots passed the existing synthetic-jitter movement,
three spectator-role changes, and reconnection trial. See **TESTING.md** and
`tests/results/*v4.0*` for exact commands and results.

Browser tests used Chromium desktop/mobile emulation, exact shipped assets,
synthetic Location/History/storage adapters, and real local Go sockets. Production
protocol tests separately used the normal Origin-validated HTTP/WebSocket handler.
Physical phones, Safari/Firefox, native deep-link/refresh/address-bar lifecycle,
public deployment, Docker execution, real packet loss, and hosting load were not
tested. The delayed-network trial is one synthetic run, not a universal latency
or FPS guarantee. The previous v3.9 timing failure remains documented historically;
it is not retroactively declared passing.
