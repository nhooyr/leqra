# leqra v3.6 — verification

## Final release checks

| Check | Result |
| --- | --- |
| Go with race detector | **326 top-level tests; 622 including subtests passed** |
| JavaScript input/replay/interpolation | **24 passed** |
| Production HTTP/WebSocket checks | **61 passed** |
| New flags, names, defaults, scoring and cache browser checks | **63 assertions passed** |
| Retained eight-seat/chat/FPS/collision browser checks | **71 assertions passed** |
| Retained HUD/friendly-fire/fullscreen/victory/sudden-death browser checks | **110 assertions passed** |
| Browser assertion total | **244 passed** |
| Synthetic-delay turning and reconnection | Passed for both local keyboard tanks |
| Other-member spectator role changes during that delay | Both controllers continue with acknowledged inputs |
| Go vet / JavaScript syntax / compiled server | Passed |
| netcode.js compared with v3.5 | Byte-for-byte identical |

These counts are tests/assertions, not that many independent full playthroughs.
Historical version-labelled results are retained but not added to the totals.
The opt-in TestBrowserFixture is skipped in normal Go runs. The regression harnesses
now explicitly select Teams in old team-specific scenarios because the actual new
room default is FFA. They retain their earlier authorization, damage, input and
scoring assertions; no production rule is relaxed for a test.

## Audit coverage

`features36_test.go` covers default format and names, Unicode validation, host-only
and atomic rule changes, publish/preset migration, forbidden Independent seat edits,
flag-safe spawn selection at every map size, and deadline/scoring/death boundaries.
The seeded Go spawn test uses 30 seeds × four map sizes × eight tanks × three spawn
passes (2,880 tank placements), checking the allied home cell and tank overlap.

The new browser suite uses pixel comparisons to verify that an overlapped flag card
cannot paint over an allied hull on desktop, portrait and landscape phone layouts.
It checks eight-seat spawns, dropped/current flag reservations through Go, names in
settings/presets/online victories, literal markup, responsive HUD geometry, legacy
migration, exact local overlaps, cutoff scoring and bounded caches.

The untouched v3.5 Go sources reproduce four failing deadline/helper assertions;
`tests/results/audit-v3.5-original-failures.txt` preserves that evidence. The copied
`tests/fixtures/audit-deadline-v3.5.go.txt` is test-only source, not part of the server.
The same checks pass in v3.6. Single grenade/shield outcomes, once-only team points
including dead high-seat allies, and no arbitrary winner after mutual destruction
pass both the reference and current tests; these are verified invariants rather
than newly claimed bug fixes. No claim of exhaustive bug freedom is made.

## Re-run Go and core JavaScript

```sh
go test -race -count=1 ./...
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs
go build -trimpath -o leqra .
```

## Production protocol

With the normal server running and optional Python websockets installed:

```sh
python tests/features36_protocol.py http://127.0.0.1:8080
```

This uses the ordinary Origin-checked WebSocket handler, not a bypass fixture.
It checks eight controllers, spectator overflow, chat attribution/history/isolation,
rate limits, kicks/resume, names, Unicode, host-only rules and team constraints.

## Browser fixture and suites

The browser tests need optional Python Playwright and Chromium. These are test
requirements only; no browser testing package is a game runtime dependency.

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:8878   go test -run '^TestBrowserFixture$' -count=1 -timeout=30m
```

In another terminal, from the same project:

```sh
python tests/features36_browser.py --url http://127.0.0.1:8878 --output test-output/features36
python tests/features35_browser.py --url http://127.0.0.1:8878 --output test-output/regression35
python tests/polish34_browser.py --url http://127.0.0.1:8878 --output test-output/regression34
python tests/network_smoothing.py http://127.0.0.1:8878 --isolated   --browser /usr/bin/chromium --local2 --roles --output test-output/network36
```

The flag grants, forced captures/hill/deaths and open worlds exist only in an
opt-in loopback `_test.go` server, not the production executable. Pages load the
exact shipped JS/CSS/HTML through asset injection because ordinary navigation is
restricted in this environment. URL, History and storage are adapters, while
multiplayer traffic uses real local Go sockets. Native Chromium fullscreen was
exercised; physical device deep-link/address-bar behavior was not.

The network test uses 60 ms base delay each way plus ordered 0–65 ms message jitter,
not real packet loss. It checks two local predictors, a remote viewer, three other-
member role changes, and automatic reconnect. Run performance tests separately
from these suites to avoid adding measurement load.

## Performance

```sh
python tests/performance36_browser.py . test-output/performance36
```

See **PERFORMANCE-v3.6.md** for the exact cache A/B and limits. The raw report is
`tests/results/performance-v3.6.json`. It measures Canvas submission, not GPU
completion; both six-second RAF samples were already approximately 60 FPS.
The optional Go benchmark smoke output is not a before/after speed claim and was
collected while browser regressions were also running.

## Scope limits

No physical phones, Safari/Firefox, public hosting, actual address-bar navigation,
real-world packet loss, Docker execution, GPU/WebGL comparison, or production
capacity test was performed. Test results and synthetic delay measurements do not
guarantee every device's latency or FPS. A WebGL renderer was not implemented.
