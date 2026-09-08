> Historical guide: command paths below reflect its original release. For the current repository layout and commands, use the [setup and development guide](README-verbose.md).

# leqra v2.1 — multiplayer movement update

## Apply the update

1. Stop the old Go server. Keep a backup of any custom deployment configuration.
2. Replace the project sources and the entire `web/` directory with this package.
3. In the `leqra-online` folder, run `go run .` and open the same server address.
4. Refresh every player's browser. A hard refresh clears any old client code.

For an executable deployment, rebuild with `go build -trimpath -o leqra .`
(`leqra.exe` on Windows), then launch the new executable. Its web files are
embedded, so replacing loose JavaScript without rebuilding the binary is not
enough. Docker Compose deployments use `docker compose up --build -d` with their
existing deployment settings.

The server reports **2.1.0** at `/healthz`; `leqra.version` in the browser
console is also **2.1.0**. Rooms and scores are in memory, so restarting closes
existing rooms. Create a fresh room after updating. No npm or database step is
required. Go is still needed only on the hosting computer.

## What changed

**Your tank responds locally.** Controls are predicted with the same 60 Hz
movement rules as the server. When authoritative state arrives, the client
replays only inputs the server has not already simulated. The acknowledgement
includes how many ticks a held command has actually run, not just its sequence
number. The previous client did not use that history and pulled its prediction
toward an older, velocity-extrapolated position.

**Corrections no longer fight the physics.** Small mismatches are absorbed in a
short-lived visual offset, while the underlying simulation immediately uses
server state plus replayed input. Turns and wall contact therefore do not keep
accumulating corrective forces in the movement calculation. Rendering also
handles the fraction between 60 Hz prediction steps for high-refresh displays.

**Other tanks follow a continuous timeline.** The previous renderer restarted
its interpolation whenever a packet arrived; uneven arrivals produced pauses
and sudden catch-up motion. The new renderer keeps a buffered timeline keyed by
server ticks, adapts its remote buffering to jitter, and does not rewind that
playhead on packet arrival. Short gaps use capped, wall-aware extrapolation.
Projectile visuals use the same timeline and a wall-aware path at bounces.

**The server sends fresher updates.** Snapshots increased from 20 to 30 per
second. A slow connection keeps only its newest pending replaceable snapshot,
not an accumulating queue of obsolete positions. Map and room messages stay
reliable. Short scheduler delays use bounded fixed-timestep catch-up. Routine
snapshots no longer rebuild the whole scoreboard and ammunition display.

Solo bots, local keyboard duels, mobile controls, rooms, scoring, and automatic
reconnection remain available. Damage and scoring are still server-controlled.

## Measured comparison

A controlled two-browser test held forward in a test-only open lane. Both
versions used real WebSockets, with **60 ms base delay in each direction plus
0–65 ms of ordered per-message jitter** injected by the test harness. Each run
held movement for 7.4 seconds; metrics excluded the first 1.2 seconds and last
0.3 seconds. The game uses a nominal forward speed of 128 world units/second.

| Measurement | Original v2.0 | Updated v2.1 |
| --- | ---: | ---: |
| Remote near-stopped render frames | 44 of 352 | 0 of 354 |
| Remote frame-speed standard deviation | 109.26 units/s | 1.21 units/s |
| Local frame-speed standard deviation | 22.30 units/s | 11.66 units/s |
| Remote average speed | 127.98 units/s | 127.81 units/s |

Lower speed variation means less stop–start motion. These are individual
controlled measurements, **not a universal performance guarantee**. The open
lane is only in an opt-in `_test.go` fixture and is not part of the playable
production maps. The baseline game code was unchanged; only the identical
measurement fixture was added to its test server.

Additional updated-client runs covered normal loopback, the above jitter
profile, and a heavier profile with 110 ms base one-way delay plus 0–100 ms
ordered jitter. The heavy run reported approximately **351–366 ms round-trip
latency**. Steady turning had no backward or near-stopped frames in the measured
windows, and automatic reconnection succeeded in all four updated-client runs.

See `tests/results/` for the recorded reports and [TESTING.md](TESTING.md) for commands.
The standard regression runs passed **47 top-level Go tests with the race
detector**, **16 JavaScript networking tests**, **24 live WebSocket checks**,
and **17 four-client browser assertions**.

## What smoothing cannot remove

The remote buffer deliberately displays other tanks slightly in the past to
hide irregular packet timing. Its target adapts between 70 and 180 ms; this is
not added to your local input prediction. Extrapolation stops after 75 ms rather
than allowing a tank to drift indefinitely through a disconnected match.

Real network delay still affects when the server receives controls and confirms
shots. Severe outages, a stalled browser, or an overloaded host can still cause
corrections. A `WEAK LINK` warning appears when state updates are stale. This
update is not a public hosting deployment or a replacement for a healthy
connection.

Testing used Chromium desktop/mobile emulation and synthetic ordered delays,
not physical phones, Safari/Firefox, real internet packet loss, or a public
host. The default game remains a single Go process with in-memory rooms.

## Implementation references

The implementation applies the general input-history and buffered-interpolation
approaches described in the following original technical articles. Its held-
input acknowledgement and exact game movement rules are specific to leqra.

- Gabriel Gambetta, Client-Side Prediction and Server Reconciliation:
  https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html
- Glenn Fiedler, Snapshot Interpolation:
  https://gafferongames.com/post/snapshot_interpolation/
