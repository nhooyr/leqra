# leqra v4.1 — actual verification and network-test limitation

## Passing checks

| Check | Result |
| --- | ---: |
| Top-level Go tests with race detector | **415 passed**, 2 opt-in tests skipped |
| Go tests including subtests | **800 passed** |
| JavaScript networking tests | **29 passed** |
| Production HTTP/WebSocket assertions | **146 passed** (127 matchmaking + 19 power/authority) |
| Browser assertions | **121 passed** (53 Ghost/Cannon/HUD + 68 matchmaking/room flows) |
| Compiled-server version, assets and fixture exclusions | **8 passed** |

Go vet, JavaScript syntax and the production build also passed. Test skips are the
long-running opt-in browser fixture and the optional movement-fixture generator.
No skipped test is counted as a pass. Historical test results remain in the
archive but are not added to current execution counts.

Cannon tests cover 4× diameter/speed, internal-wall piercing, all outer sides,
corners, rim-touching muzzle, all eight launchers, returning self-damage, shields,
cooldowns, first-tank stopping and bounded lifetime. Ghost tests cover independent
refresh/stacking, boosted movement, boundary constraints, damage, wall firing,
safe expiry, bots, lives/respawns, rules permissions and authoritative snapshots.

Four generated trajectories give **480 steps of Go/local-browser movement
agreement**, including Ghost + speed expiry and wall crossings. Five additional
Node tests cover the same movement callback used by prediction, fractional-frame
expiry, remote interpolation and independent input replay for two keyboard pilots.
This is not a blanket proof of perfect prediction under every network condition.

The live browser feature run used a real Go fixture for deterministic grants and
wall positions. Both local keyboard tanks crossed a wall at boosted speed, fired
boundary-ricocheting Cannon rounds visible to a phone-emulated spectator, reconnected
with their remaining Ghost buffs, and safely cleared walls on expiry. Production
protocol tests separately ran through the normal Origin-validated handler without
grants. The shipped executable returns 404 for the deterministic fixture paths.

UI tests covered desktop **1365×950**, portrait **390×844** and **320×568**, and
landscape **844×390**. All ten legend icons match maze icons, all four stacked buff
timers fit, and collecting/expiring buffs does not change arena dimensions. Both
local and online bot removal are one click; human confirmations remain.

## Synthetic jitter benchmark did not pass

The existing two-local-player `network_smoothing.py --local2 --roles` test ran
with **60 ms injected base delay each way** plus ordered per-message jitter
`[0,45,8,27,65,2,30,12]` milliseconds. It measures steady turning, then has later
spectator-role-change and reconnect steps. Assertions were not relaxed.

- **v4.1 attempt 1:** failed the remote near-stopped-frame limit. Both remote tanks
  had 5 near-stopped frames, above the permitted 2. Local motion had no backwards
  or near-stopped frames. The test stopped before its later role-change/reconnect
  portion.
- **v4.1 attempt 2:** no near-stopped or backward frames were measured, but remote
  angular-speed standard deviation was about **1.441 rad/s**, above its **0.65**
  threshold. It likewise stopped before the later portion.
- **Unmodified v4.0 control:** a separate sequential run with the original archive's
  Go server and browser assets also failed. Each local tank had one backwards
  frame; remote angular-speed standard deviation was about **1.133 rad/s**.

The control shows that a benchmark failure also occurs without the new gameplay
code in this environment. It does **not** establish that v4.1 has identical WAN
performance, that all misses have the same cause, or that networking is fully
optimized. These were individual runs with different observed RTTs and browser
scheduling, not a statistical performance study. No universal FPS improvement,
latency improvement or full jitter-regression pass is claimed.

The feature suite's separate real-socket reconnection check **did pass**. It is
not substituted for the failed synthetic-jitter stress test. Both failing v4.1
logs, the control log and parsed measurements are preserved in `tests/results/`.

## Test environment and boundaries

Tests used Chromium **144.0.7559.96**, desktop/mobile emulation, the exact shipped
assets and local Go servers. Location, History and storage were adapted for
isolated browser pages because normal navigation is restricted in this environment.
Canvas, DOM interactions, key/pointer input and WebSockets remained real.

No physical phone, Safari/Firefox, speaker-output, public hosting, real packet
loss, Docker runtime or production capacity test was performed. The ghost tests
use opt-in `_test.go` grant/map helpers, never a production debug endpoint.
Source packages are not an already deployed public service.
