# leqra v3.4 — verification

## Final recorded checks

| Check | Result |
| --- | --- |
| Go tests with race detector | **294 top-level tests; 472 including subtests passed** |
| Go vet, compiled Go server, JavaScript syntax | Passed |
| JavaScript networking tests | **24 passed** |
| Production HTTP/WebSocket checks | **143 passed** |
| New arena/feedback/combat browser suite | **112 assertions passed** |
| Rules, presets, remapping and objective browser regression | **108 assertions passed** |
| Spectator browser regression | **82 assertions passed** |
| Unified room, weapons and controller browser regression | **150 assertions passed** |
| Browser total | **452 assertions passed** |
| Heavy synthetic-delay motion and reconnection | Passed for both local pilots |
| Other members changing roles during that delay | Both held controllers continued; acknowledgements advanced |
| Embedded assets | Production server served exact shipped HTML/CSS/JS bytes |
| Actual Chromium fullscreen | Enter, expand, exit and restore sidebar passed |

These are assertion counts, not that many independent end-to-end scenarios.
`TestBrowserFixture` remains opt-in and skipped in normal Go test runs. Current
reports are under `tests/results/*v3.4*`. Older version-labelled reports are history
and are not added to the counts above. The core `web/netcode.js` is byte-for-byte
unchanged from v3.3. The updated integration clamps snapshot timing and controls
announcements independently of interpolation.

The production protocol total is 44 core, 21 arbitrary-room-name, 17 unified-room,
11 secondary-callsign, 21 rules/objective and 29 spectator assertions. These suites
use the normal HTTP/WebSocket handler, including Origin checks, not fixture state
grants. New host-only friendly-fire checks also run in Go and against real browser
sockets. Retained browser helpers now dismiss the new intended victory modal before
opening setup controls; they do not bypass its permission or gameplay checks.

## New v3.4 coverage and reproduced bugs

`polish34_test.go` covers default/serialized/validated friendly fire, self-damage in
all four seats for both human and bot tanks, every ally pair, shields, real shell,
missile, grenade and laser ally hits, enemy-only bot/seeker targeting with friendly
fire on, host authorization, tied/untied objective clocks, score freezing, disabled
respawns, final-side/FFA wins, mutual-destruction replay, late arrivals, replaced
occupants, new-match resets and an empty-room terminal condition.

`polish34_browser.py` uses shipped code and optional v3.3 baseline assets. It
reproduced the original speed/shield HUD resize on a 390×844 viewport: the arena
height changed from 534.3125 to 525.078125 CSS pixels because the HUD gained height.
The updated one/two-local-pilot checks held arena bounds, HUD height and canvas
backing dimensions constant across all seven powers, expiry and death at 1365×950,
390×844, 320×568 and 844×390. Real window/orientation/layout-mode changes may resize.

The same baseline test reproduced a false GO by placing snapshot receipt 12 ms
after the animation frame timestamp. Current code does not display GO in that
case, after a CTF death, or near a missile. GO is limited to the actual start
transition. Both layout/timing reproductions are included in the 112 assertions.
Without the optional baseline archive this suite runs 110 assertions instead.

The browser suite checks the friendly-fire editor/preset field, guest read-only
controls and forged command rejection, sidebar persistence, real headless Chromium
fullscreen, local CTF/Hill sudden death, persistent no-respawn status, visible flags,
team victory popups on the host/guest/spectator, no popup reopening on repeated
snapshots, and rematch reset with spectator roles preserved. Existing regressions
exercise room capacity, local P2 naming/input/ammo, watch prompts, swaps and kicks,
objectives and remapping on the final assets. See the named JSON reports.

The heavy delayed-network run used 110 ms base one-way delay plus 0–100 ms ordered
per-message jitter. It exercised both local keyboard pilots, remote interpolation,
three other-member spectator-role changes and reconnection. This is a synthetic
ordered-delay test, not real packet loss or a public hosting capacity guarantee.

## Repeat the new browser checks

After ordinary Go/JS checks, start the opt-in test-only loopback fixture:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:8878 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=90m
```

In another terminal with optional Playwright and WebSockets test dependencies:

```sh
python tests/polish34_browser.py --url http://127.0.0.1:8878 \
  --browser /usr/bin/chromium --output test-output/polish34
# Add --baseline /path/to/leqra-online-v3.3.zip to reproduce the old bugs.
python tests/features32_browser.py --url http://127.0.0.1:8878 --output test-output/features32
python tests/spectators_browser.py --url http://127.0.0.1:8878 --output test-output/spectators
python tests/unified_room_browser.py --url http://127.0.0.1:8878 --output test-output/unified
python tests/network_smoothing.py http://127.0.0.1:8878 --isolated \
  --browser /usr/bin/chromium --motion turn --profile heavy --local2 --roles \
  --output test-output/network34
```

Adjust the browser executable path to your installation. Run the timing-sensitive
network test separately from other CPU-intensive tests. Test endpoints exist only
in `_test.go` and the explicit loopback fixture, never the production executable.

## Limits

Browser testing uses Chromium desktop/mobile emulation with exact shipped assets,
synthetic Location/History/storage adapters and real local Go sockets. Actual
Chromium fullscreen was tested; physical phones, Safari/Firefox, normal address-bar
navigation, public internet deployment, Docker execution, real packet loss and
hosting capacity were not. Optional screenshots are test captures, not physical-device
proof. Persisted settings use the normal browser storage APIs; adapters exercise
content/restore/error paths rather than cross-browser persistence guarantees.

## Spectator coverage

`spectators_test.go` covers distinct membership and gameplay identities, required
watch callsigns, full-room fallback, all-client viewer visibility, spectators not
readying/firing/scoring, round/rematch persistence, role changes and combat cleanup,
no extra elimination life, objective flag drops and delayed respawns, spectator
host controls, ownership and authorization, immutable swap targets, atomic swaps
at full arena/gallery capacity, reconnect and kick revocation, expiry, host handoff,
secondary-local input/naming/cascade removal, and publishing a spectating local host.

Concurrent promotion of the last free tank place permits only one player. Tests
also cover swapping a primary with its own spectating secondary and back, retaining
controller ownership. A different member's role change must not clear unrelated
players' held inputs or rewind server acknowledgement history.

`spectators_protocol.py` checks these public operations through the normal
production HTTP/WebSocket handler with its ordinary Origin validation. It uses
no test-only state-grant endpoints. Existing suites also check malformed input,
transport bounds, names, room isolation, guest permission failures and objectives.

`spectators_browser.py` exercises the actual controls: callsign-first watch prompt,
no connection before confirmation, empty-name rejection, valid Unicode watch URLs,
localhost warning with watch flag retained, full-room spectator fallback, separate
viewer lists, host swaps/kicks, no auto-rejoin after kick, owner/P2 role changes,
normal reconnect, simulated refresh/resume, rematches, bot-only play, and sharing a
local spectating host. It checks that a spectating browser sends no gameplay inputs
and that roles outside 0–3 create no tank. The suite also checks unchanged-controller
sequence chronology and own-primary/P2 exchanges through the real Go server.

Room, watch prompt, gallery, swap dialog and spectator gameplay layouts cover
320×568, 390×844, 844×390 and 1365×950. Buttons are hit-tested after scrolling;
spectating hides unused primary touch controls. Existing browser regression covers
remapping, save/load adapters, independent ammo, missile warnings, power-ups, CTF
and hill scoring, keyboard/multi-touch, team rules, and Go/JavaScript weapon parity.

## Run checks

```sh
go test -race ./...
go vet ./...
go build -trimpath -o leqra .
node --test tests/netcode.test.cjs
node --check web/game.js
node --check web/netcode.js
```

Only Go is required to build/run the game. Node, Python, Playwright and WebSockets
are optional test tools, not game runtime dependencies. With a normal server running:

```sh
python tests/protocol_smoke.py http://127.0.0.1:8080
python tests/expansion_protocol.py http://127.0.0.1:8080
python tests/unified_room_protocol.py http://127.0.0.1:8080
python tests/gameplay31_protocol.py http://127.0.0.1:8080
python tests/features32_protocol.py http://127.0.0.1:8080
python tests/spectators_protocol.py http://127.0.0.1:8080
```

The fifth-visitor expectations in the old core protocol tests were deliberately
updated: the correct result is now spectator admission, not a room-full error.
Go join-capacity/concurrency tests likewise count combatants and viewers separately.
No permission, damage, range, ready-state or reconnect protection test was removed.

## Browser / network fixture

Start this test-only server on loopback in another terminal:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:8878 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=30m
```

Then run suites (the browser executable path can be adjusted):

```sh
python tests/spectators_browser.py --url http://127.0.0.1:8878 --browser /usr/bin/chromium
python tests/features32_browser.py --url http://127.0.0.1:8878 --browser /usr/bin/chromium
python tests/unified_room_browser.py --url http://127.0.0.1:8878 --browser /usr/bin/chromium
python tests/network_smoothing.py http://127.0.0.1:8878 --isolated \
  --browser /usr/bin/chromium --motion turn --profile heavy --local2 --roles
```

The last run used 110 ms base delay **in each direction**, plus ordered per-message
jitter of 0–100 ms. It measures both locally controlled tanks and remote rendering,
then changes a third member between spectating and playing three times while both
local pilots keep holding Turn. Server angles and acknowledged inputs must keep
advancing; role changes must not clear those held controls. Finally it disconnects
and reconnects the controller with delay still active. Reports include raw measured
values, not a new universal movement-quality or latency guarantee.

Deterministic state-grant/objective/lane endpoints exist only in the opt-in
`_test.go` server. They are absent from production `go run .` and compiled binaries.
Ordinary production socket checks are run separately without those endpoints.

## Limitations

Browser tests use Chromium desktop/mobile emulation, the exact shipped assets,
synthetic Location/History/storage adapters, and real loopback Go WebSockets.
The execution environment restricts ordinary browser navigation. URL generation,
confirmation gates and resume credentials are tested through adapters; actual
address-bar navigation, physical-device refresh lifecycle and localStorage disk
persistence were not tested. Keyboard and native dialog/touch event paths were used.

Physical phones, Safari/Firefox, public internet hosting, real packet loss, Docker
execution, load/capacity, gamepads and a third-party security audit were not tested.
The custom WebSocket transport remains unaudited and not Autobahn-certified.
The 16-viewer cap is a bound, not a proven simultaneous-room capacity promise.
Older browser scripts expressing obsolete P2 Enter controls are historical; use
`features32_browser.py` and `unified_room_browser.py` for current defaults.
