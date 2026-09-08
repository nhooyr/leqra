# leqra v4.2 — audit and actual test results

## Results for the delivered source

| Check | Observed result |
| --- | ---: |
| Top-level Go tests, race detector enabled | **419 passed** |
| Go tests including subtests | **811 passed** |
| Opt-in Go tests skipped | **2**, not counted as passes |
| JavaScript networking/presentation tests | **42 passed** (29 existing + 13 new) |
| Production HTTP/WebSocket assertions | **147 passed** (127 matchmaking + 20 power/authority) |
| Browser assertions | **162 passed** (41 new firing + 53 Ghost/Cannon + 68 matchmaking) |
| Original-version bug reproduction and four-viewport regressions | **Passed**, reported separately from the 162 assertions |
| Two-local-player injected-jitter movement/role/reconnect regression | **Passed this run** |
| Compiled server version/embedded assets/test-endpoint exclusion | **8 checks passed** |

Go vet, JavaScript syntax and the production executable build passed. The detailed
logs and JSON records are in `tests/results/v4.2/`; compressed raw frame records
are included. No historical run is added to the above totals. Commands are in
**TESTING.md**. The source manifest allows checking the delivered files.

## Reproduced defects, not inferred FPS claims

`feel42_repro.py` loads the original v4.1 assets and the updated assets separately.
It uses a controlled monotonic clock and explicit snapshots to make presentation
bugs independent of scheduler timing.

| Reproduction | Original v4.1 | Updated v4.2 |
| --- | --- | --- |
| General HUD update after setting a live cooldown | Overwrites **0.3s** with **FIRE** | Does not overwrite the combat label |
| Repeated frozen result snapshots | **4** distinct cooldown-fill values | **1** stable fill, **ROUND COMPLETE** |
| New remote projectile entering the buffer | Displays x=338.8, then moves backward to x=324.7 | Waits for its buffered birth; first eligible sample is x=324.7 |

Coordinates are world units in a deliberately simple straight lane, not pixels
or a speed benchmark. The newer check also gives the local pilot a charged laser
while five ordinary rounds occupy the ammo slots: the cosmetic laser still fires,
its confirmed beam does not restart, and the authoritative rounds are untouched.

Four viewport checks cover **1365×950**, **390×844**, **320×568** and **844×390**.
Both local panels agree on playing, countdown, paused, round-complete and
match-complete states; changing those labels does not resize the arena. These are
Chromium desktop and mobile emulations, not physical-device testing.

## Real-socket firing with injected latency

`feel42_live.py` uses a real Go fixture with two local keyboard pilots and a
phone-emulated online spectator. The wrapper adds **90 ms base one-way delay**
and ordered per-message jitter `[0,25,8,40,3,12]` milliseconds. DOM, Canvas,
keyboard input and WebSockets remain real; Location/History/storage are adapted.
The test-only arena and temporary invulnerability isolate presentation from
uncontrolled combat outcomes and are not enabled in the production server.

Both pilots fire Standard, Rapid, Scatter, Homing, Grenade, Cannon and Laser.
Checks verify that Go accepts the independent shots, their local sound is not
replayed on acknowledgement, and ordinary/Cannon projectiles do not move backward
at the preview-to-confirmation handoff. Grenade remote detonation remains specific
to its owner. A round win with a nonzero cooldown remains visually stable across
real snapshots; completed-match UI and reconnect cleanup pass too.

For the six projectile cases in this final individual run, the first cosmetic
projectile was recorded **8.5–13.8 ms** after the pre-key measurement timestamp,
before its server acknowledgement. This is a sampled browser-render response in
an isolated test, **not** end-to-end input hardware latency, server damage latency,
a percentile estimate, physical screen scanout or a guarantee on other devices.
Laser response is checked behaviorally, not assigned an invented projectile time.
Raw per-frame records and the exact per-weapon observations are supplied.

During development, the first new live test caught a small backward correction
when confirmation arrived. The fix switched to an absolute local birth clock
instead of a packet-relative clock. The passing final test does not conceal that
iteration or claim all trajectories and network failures have been exhaustively
proven smooth. Homing changes, rejected shots and long outages can still require
visible authoritative corrections.

## Existing movement/jitter stress check

The existing `network_smoothing.py --local2 --roles` thresholds were **not relaxed**.
This run uses **60 ms base one-way delay** and ordered per-message jitter
`[0,45,8,27,65,2,30,12]` milliseconds. It measures continuous turning, makes three
other-member spectator role changes, and reconnects the controller.

| Measured render track | Frames | Angular-speed standard deviation | Backward / near-stopped frames |
| --- | ---: | ---: | ---: |
| Local Player 1 | 353 | 0.378 rad/s | **0 / 0** |
| Remote view of Player 1 | 352 | 0.029 rad/s | **0 / 0** |
| Local Player 2 | 353 | 0.435 rad/s | **0 / 0** |
| Remote view of Player 2 | 352 | 0.029 rad/s | **0 / 0** |

Both local tanks continue moving through the role changes and resume after
reconnection. These are one run's values. The historical v4.1/v4.0 failures remain
in their versioned reports; they are not retroactively counted as passing. This
is not a controlled statistical before/after WAN comparison or a hosting-capacity
claim. Angular gap extrapolation is intentionally bounded to 75 ms.

## Authority and cleanup checks

The new Go tests cover accepted/rejected volley serials, scatter pellet/life IDs,
serialization, ordinary post-result cooldown/score freezing, and unchanged Cannon
size/speed. The JavaScript tests cover local preview eligibility, charge and slot
bounds, monotonic displayed cooldowns, no authority mutation, grenade holds,
preview expiry, life resets, independent pilots and bounded angular extrapolation.

Existing Ghost/Cannon, matchmaking, room ownership, role handoff, spectator,
reconnect and mobile HUD regressions also ran. The normal production HTTP handler
rejects forged power/rule operations; deterministic grant/arena paths, including
`/_fixture/combat42`, return 404 in the compiled production executable. The bytes
served for all four web assets match the shipped files.

## What was optimized; what was not measured

Online cosmetic updates now execute once per rendered frame rather than once
per 120 Hz simulation iteration. Fixed-step online movement prediction is kept
separate. Particle drag is reused within each update. Unchanged Fire styles and
attributes are skipped; duplicate forced control packets for an unaffected local
pilot are suppressed, retaining ordinary heartbeat and changed-input delivery.
Some hot menu checks avoid constructing temporary arrays. Existing indexed walls,
map/tank caches and single-encode-per-room snapshots remain in use.

These are concrete reductions in repeated work. **No new device FPS, GPU execution,
CPU-throughput or server-capacity benchmark was performed for v4.2**, and no overall
percentage speedup is claimed. The volley/life metadata adds some snapshot bytes;
bounded local previews also have a rendering cost. No WebGL renderer is included.

## Environment and boundaries

Chromium **144.0.7559.96**, with desktop/mobile emulation, ran against local Go
servers. Browser navigation is restricted in this environment, so the harness
injects exact shipped assets with synthetic URL/History/storage objects. Normal
production WebSocket/HTTP tests run separately through the Origin-validated handler.

No physical phones, Safari/Firefox, physical speaker-output/scanout testing, real
internet packet loss, public deployment, Docker execution or production load test
was performed. Client prediction cannot remove real server/network latency and
does not make every possible future bug impossible. This is source for your
running server, not an already-hosted service.
