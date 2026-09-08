# leqra v4.5 — verification, audit and limits

## Final executed checks

| Check | Result |
| --- | --- |
| Go race suite | **442 top-level tests passed**, 2 opt-in tests skipped, 0 failed; **834 passes including subtests** |
| JavaScript unit tests | **56 passed**, 0 failed |
| Focused production WebSocket assertions | **8 passed** |
| Focused Chromium browser assertions | **18 passed**, no uncaught browser errors |
| Script syntax | `theme.js`, `game.js`, `netcode.js` passed |
| `go vet ./...` | Passed |
| Compiled Go server | Passed |
| Embedded source/served assets | **7/7 byte-identical** |

The two skipped top-level Go tests are the existing opt-in browser fixture and movement
fixture writer. They are not counted as passes. Machine-readable race output is in
`tests/results/v4.5/go-race.json`; the focused browser/protocol records and embedded
asset hashes are in the same directory.

## What the new tests cover

### Paint authority and teams

- An online human can paint their own Free-for-all tank.
- A host cannot paint a remote online human in FFA.
- A host can paint a bot; a controller can paint its attached local P2.
- Team mode clears individual FFA paint and rejects later paint requests.
- Team tank colors come from the host-selected team colors even when old personal paint
  existed previously.
- `configure` cannot bypass the owner-aware paint action.
- Stale participant incarnation IDs and invalid palette indices remain rejected.
- Team-room payloads omit irrelevant personal paint metadata.
- A private FFA color is retained in the source lobby but not copied into a public team
  matchmaking battle.

### Callsigns and UI

- Both local tank labels use their actual callsigns with Local Player 2 active.
- Arena labels contain neither P1/P2 replacement text nor T1/T2/T3/T4 team suffixes.
- Individual paint controls disappear in Teams and appear only for permitted FFA owners.
- Light/Auto appearance controls are absent; the dark interface uses neon blue.
- Switching FFA → Teams updates local and remote tank paint to authoritative team colors.

### Speed stacking and pickup weighting

- Speed stacks from one through five and refreshes one shared six-second timer.
- A sixth pickup leaves the count capped at five while refreshing the timer.
- Human, bot and online prediction movement use the same additive stack multipliers.
- Five-stack movement and turning remain bounded at wall contact without tunneling.
- Speed expiry clears all stacks; respawns/new lives reset them.
- Shield and Speed each use weight 3; other enabled pickups use weight 1.
- Empty/singleton/disabled weighted pools keep their existing safety behavior.

### Production protocol

The normal Origin-validated production WebSocket handler was used, not a fixture grant
endpoint. The focused live checks cover FFA self-paint, denied host repaint, configure
bypass rejection, team-state paint cleanup, team paint lock, authoritative opposing team
colors, fresh Speed stack state, and ignored client-forged Speed fields.

## Bugs fixed during audit

Two hidden state bugs were found and fixed:

1. FFA paint could remain stored through a Team-mode period and unexpectedly reappear
   after returning to FFA. Entering Teams now clears it.
2. A team matchmaking copy could retain an unused private FFA paint override. The public
   battle copy now clears it while the original lobby preference remains untouched.

No additional point-award or tank-death bug was found in this pass. The complete race
suite still exercises elimination/team scoring, objective deadlines, sudden death,
shields, self-damage, friendly fire, statistics, spectators and high-numbered seats.
This is a targeted audit, not a proof that no undiscovered bug exists.

## Optimization changes checked

The code audit removed light-theme runtime state and several unnecessary allocations:

- no browser color-scheme media listener or theme storage synchronization;
- no per-bot `filter().sort()` allocation to pick the nearest/priority enemy;
- boosted bot tuning cached until difficulty or stack count changes;
- no temporary `{x,y}` point object in one per-step ally-risk check;
- no temporary tank clone for cached-hull paint substitution;
- no useless FFA `colorIndex` field in team-room player payloads.

No global FPS percentage is claimed from those source-level improvements. The renderer,
network and AI have multiple independent bottlenecks and this pass did not run a new
physical-device GPU benchmark.

## Commands

From `leqra-online`:

```sh
go test -race -count=1 -json ./... > tests/results/v4.5/go-race.json
go vet ./...
node --check web/theme.js
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs tests/combat42.test.cjs \
  tests/palette44.test.cjs tests/theme43.test.cjs
go build -trimpath -o leqra .
```

Focused Chromium regression:

```sh
python3 tests/polish45_browser.py
```

Focused production protocol check, with a compiled server already running:

```sh
python3 tests/polish45_protocol.py http://127.0.0.1:8465
```

## Not exercised

Physical phones, Safari/Firefox, native public-WAN matchmaking, real packet loss, Docker
execution, sustained production capacity, physical audio output and hardware-GPU
profiling were not exercised. Passing local/synthetic tests does not guarantee a
particular FPS or latency on every device/network.
