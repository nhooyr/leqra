# leqra v4.0 verification

## Checks actually executed

- **402 top-level Go tests passed with the race detector**, 786 including subtests.
  `TestBrowserFixture` is deliberately skipped without its explicit opt-in.
- **24 JavaScript netcode tests passed**.
- **127 production HTTP/WebSocket assertions passed**, against the ordinary
  Origin-validated server, with no test grants or substituted network operations.
- **114 browser assertions passed**: 68 matchmaking/room flows and 46 existing
  Cannon/controls/legend/mobile-HUD regressions. The latter script differs from
  v3.9's check only in its expected application/report version.
- `go vet ./...`, JavaScript syntax checks, a compiled server build and five
  embedded-browser-asset byte comparisons passed. Test grant/map endpoints
  return 404 in the production binary.
- The existing two-local-player synthetic-jitter motion/reconnection regression
  passed, including three unrelated spectator-role transitions with held input.
  This run used 60 ms base delay in each direction plus deterministic ordered
  0–65 ms message jitter. It is not a physical-network or universal FPS benchmark.

Current execution reports are `tests/results/*v4.0*`. Older reports and
`TESTING-v3.9.md` are historical, not newly executed checks. One earlier browser
attempt reached the final requeue case but its test predicate accessed a temporarily
null queue. The predicate was corrected to wait for the queue; the complete final
68-check run then passed. No gameplay condition was mocked to make it pass.

## Server coverage

Tests cover all six exact populations/maps/rules, party-size/FFA validation,
remote confirmation, stale accept/cancel IDs, host authorization, spectator
isolation, concurrent joins, exact packing against 600 generated feasibility
cases, source-room reservations, two independent local-P2 parties, input ownership,
stale pre-transfer commands, duplicate membership, disconnect/expiry cleanup,
room-limit blocking, matched-room admin/admission denial, both directions of
credential handoff, original team/bot/rule preservation and return, forfeit
statistics, and credential-free public packets. The existing engine, transport,
weapons, objectives, scoring, stats and security tests also ran.

The live production suite forms all six queues with actual WebSockets, runs each
through its server countdown into play, checks both full-size parties and 2+1 vs 3,
returns every member to their source room, tests chat/viewer isolation and a
refresh-equivalent reconnect using the old origin credential. No bot impostors
are used in place of queued humans; test clients send the same JSON as browsers.

## Browser coverage

Actual DOM/key/pointer actions exercise the six-card chooser at **1365×950,
390×844, 320×568 and 844×390**, including scroll bounds and cancel behavior.
The suite publishes the default local room, queues only the owner (not their
three bots), cancels, then tests a host + named local P2 + remote friend with a
source spectator. It checks consent, chat, automatic 3v3 CTF transfer, one shared
team, input acknowledgements, P2 ammo, watch-link callsign confirmation, reconnect,
forfeit/victory statistics, original-lobby return and another consent cycle.

The browser harness injects the **exact shipped assets** into isolated pages
because ordinary navigation is restricted in this environment. Location, History
and storage have explicit test adapters; controls, canvas drawing, WebSockets,
server simulation and gameplay are real. The opt-in Go fixture accepts the opaque
browser test origin and contains historical deterministic weapon/map endpoints.
These paths and the opaque-origin allowance do not exist in the production build.
The separate live protocol suite uses the production origin check unchanged.

## Repeat core checks

```sh
go test -race -count=1 ./...
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs
go build -trimpath -o leqra .
```

With a production server running (testing may create many temporary rooms):

```sh
python tests/matchmaking_protocol.py http://127.0.0.1:8080 --output matchmaking-live.json
```

Optional browser tests require Python `playwright` and `websockets`, plus Chromium.
Those packages are **not** runtime dependencies of the Go game. For the opaque-page
harness, in another terminal start its explicitly enabled, loopback-only fixture:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18041 \
  go test -run '^TestBrowserFixture$' -timeout=0
python tests/matchmaking_browser.py http://127.0.0.1:18041 --output test-output/queues
python tests/cannon40_regression_browser.py --output test-output/cannon
python tests/network_smoothing.py http://127.0.0.1:18041 --isolated \
  --browser /usr/bin/chromium --profile jitter --local2 --roles \
  --output test-output/network
```

The new queue browser scripts use `/usr/bin/chromium`; adjust their launch path
for another test installation. Never enable the fixture on a public interface.

## Bounded packing microbenchmark

```sh
go test -run '^$' -bench '^BenchmarkMatchmakingIncompatibleParties$' -benchmem -count=3
```

The deliberately impossible 3v3 pool of **256 two-player parties** took about
**9.2–9.5 microseconds per packing call**, with 2,176 bytes and seven allocations,
in three local runs on this container. The code tries at most one anchor per
party size instead of repeating an equivalent failed search for every ticket.
This is only team-packing CPU work, not total matchmaking latency, live hosting
capacity, whole-frame time, network delivery or a measured FPS improvement.

## Limits

No physical phones, Safari/Firefox, native address-bar/deep-link/refresh lifecycle,
public internet deployment, real packet loss, Docker execution, production
capacity/load, ranking, region selection or independent security audit was tested.
A refreshed browser is represented by a new socket and its actual prior token in
server tests; real mobile OS tab suspension differs. Synthetic latency results
are individual measurements. The existing custom WebSocket transport has not had
an independent full conformance audit. Matchmaking preserves server authority but
is not an account system or comprehensive anti-cheat.
