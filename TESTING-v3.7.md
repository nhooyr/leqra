# leqra v3.7 — verification

## Checks executed against this release

| Check | Result |
| --- | --- |
| Go with race detector | 345 top-level tests; 653 including subtests passed |
| JavaScript input/replay/interpolation tests | 24 passed |
| Production HTTP/WebSocket regression | 61 checks passed |
| New post-match statistics browser suite | 177 assertions passed |
| Prior flags/teams/defaults/scoring/cache browser regression | 63 assertions passed |
| Browser assertions total | 240 passed |
| Delayed-network two-local-player turning, role changes and reconnection | Passed |
| Go vet / JavaScript syntax / compiled server | Passed |
| Compiled web assets match the shipped web files | Passed |
| Core netcode.js compared with v3.6 | Byte-for-byte identical |

Counts represent tests/assertions, not independent full playthroughs. Repeated
development runs are not added together. Prior version-labelled reports are
historical, not additional v3.7 executions. The opt-in TestBrowserFixture is
skipped in ordinary Go test runs.

## New coverage

`stats_test.go` checks actual weapon damage, all eight indices, humans/bots,
shield/invulnerability handling, self-destructs, teammate kills and a grenade
that kills its shooter before another victim. It covers stats across rounds and
respawns, final winning captures, manual versus automatic flag returns,
uncontested allied Hill time without multiplied team points, protection and
contesting, sudden death, final-tick duration, membership/seat reuse and duplicate
names. Departed participants retain their totals without an invented death;
watch-only spectators receive no combat rows. It also checks immutable reports,
credential-free serialization, absence of reports from live snapshots, bounded
membership churn and ignored client-forged counters.

`tests/stats37_browser.py` executes local damage/objective logic and the actual
Go-backed result flow. It checks both local pilots, eight result entries,
mode-specific metrics, winning-team markers, safe literal names, existing-player
history and new-match resets. Both players and spectators, including a late
viewer and a resumed connection, see the same frozen report. The new connection
must receive an explicit resumed welcome; a stale cached report is not treated
as proof of reconnection. Repeated final snapshots must not reopen the popup.

Layouts tested: 1365×950 desktop, 390×844 phone, 320×568 compact phone and
844×390 landscape phone, in Elimination, CTF and Hill. Checks verify no horizontal
page/dialog overflow, initial focus at the congratulations heading, labeled mobile
cards, scrollable results and the visible sticky Back to Room action. Screenshots
were inspected for desktop and compact portrait.

The v3.6 feature browser/protocol harnesses were retained, with their release
version assertions/report tags updated. They still exercise four custom team
names, eight seats, chat, spectators, authority, safe flag layering/spawning,
objective timing and rendering-cache bounds. `TESTING-v3.6.md` preserves the
previous release's broader historical audit rather than implying it was all
rerun here.

## Reproduce

```sh
go test -race -count=1 ./...
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs
go build -trimpath -o leqra .
```

For the optional browser suites, install Python Playwright and Chromium in your
test environment. Run the opt-in test fixture in a separate terminal:

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:8878 \
  go test -run '^TestBrowserFixture$' -v -timeout 45m
```

Then:

```sh
python tests/stats37_browser.py --url http://127.0.0.1:8878 \
  --browser /usr/bin/chromium --output test-output/stats37
python tests/features36_browser.py --url http://127.0.0.1:8878 \
  --browser /usr/bin/chromium --output test-output/regression36
python tests/network_smoothing.py http://127.0.0.1:8878 --isolated \
  --browser /usr/bin/chromium --local2 --roles --output test-output/network37
```

The report fixtures exist **only in `_test.go`**, behind the opt-in loopback
server. They are not routes in `go run .` or the compiled production binary.
Run the live production protocol regression against a normal server separately:

```sh
go run . -addr 127.0.0.1:8888
# In another terminal:
python tests/features36_protocol.py http://127.0.0.1:8888
```

The production protocol runner uses the existing `websockets` Python dependency
for testing only. No third-party package is required to run the actual game.

## Results and limitations

Current release results are stored under `tests/results/*v3.7*`. The stats browser
report contains the check-by-check results, the Go summary records passed test
names/counts and race-run completion, and the network report records the
synthetic profile and observed motion. These are individual runs, not a capacity
or latency guarantee.

Browser tests use exact shipped assets injected into Chromium pages with
synthetic Location/History/storage adapters and real loopback Go WebSockets.
They do not test physical phones, Safari/Firefox, actual browser address-bar
navigation, public internet deployment, Docker execution or production hosting
capacity. The injected network profile models ordered delay/jitter, not actual
internet packet loss. The FPS performance benchmark from v3.6 was not re-run;
this release makes no new FPS speed-up claim.
