# leqra v4.20 test notes

## Final automated verification

The release-version validation completed with:

- **469** race-enabled top-level Go tests run;
- **870** passing Go test/subtest events;
- **0** Go failures and **2** intentionally opt-in fixture skips;
- **56/56** JavaScript/Node tests;
- **81/81** real-Go-WebSocket matchmaking/browser checks;
- **23/23** Safari/WebKit identity-path checks;
- **12/12** branding/storage-migration checks;
- **16/16** retained desktop gameplay/HUD checks;
- **6/6** narrow-mobile checks;
- **8/8** retained v4.18 presentation/layout checks;
- `go vet ./...`, JavaScript syntax checks, and `go build -trimpath` all passed.

The real matchmaking run covers the new host-only room rename, propagation to a remote 320px client, invite-URL updates, the separate red opponent-chat button, enemy-only delivery, teammate non-delivery, minimized-chat notification path, no mobile header overflow, spectator filtering, reconnects, the **End match** label, results actions, rematch behavior, and reserved-party return. No uncaught browser errors occurred.

The presentation regression verifies that a losing local player receives red **DEFEAT**, a crossbones/defeat icon below the heading, and no congratulatory copy. It also retains the pause/Controls aspect-ratio regression, P1/P2 TANK DOWN behavior, pickup timing, and Safari recommendation removal.

## Server tests added for v4.20

Dedicated Go regressions verify:

1. Room rename moves the hub map key atomically and broadcasts the new code.
2. Guests cannot rename; collisions are rejected; an in-flight reconnect using the old code/token follows the renamed room.
3. Opponent chat reaches the sender and opposing matchmaking side but not the sender's teammate.
4. Reconnected opponent-chat history is filtered by side so same-team tactical messages do not leak.

## Performance checks

Current server benchmark sample on the test host:

```text
BenchmarkEightBotsHuge35-5      39109 ns/op      80 B/op    0 allocs/op
BenchmarkRoomBroadcast35-5      23188 ns/op    5351 B/op    2 allocs/op
```

v4.20 additionally batches restored chat-message DOM creation and eliminates the temporary per-message `map[*Client]bool` used by the first opponent-chat implementation. These changes are intended to reduce short-lived allocation/layout work; the benchmark figures above are not a whole-game FPS or hosting-capacity claim.

## Safari note

Native Safari/WebKit is not installed in this build environment. Safari desktop/iPhone/iPad behavior is exercised using the shipped WebKit/iOS detection and CSS/input paths under Safari identities in system Chromium. Those checks include the v4.19 WebKit optimization behavior and verify the desktop Chrome recommendation is gone, but they are not a native-Safari FPS benchmark. Physical macOS/iPhone/iPad Safari remains the final platform acceptance target.

## Commands

```sh
go test -race -count=1 -json ./...
go vet ./...
node --check web/theme.js
node --check web/netcode.js
node --check web/game.js
node --test tests/*.test.cjs
python3 tests/branding417_browser.py --output tests/results/v4.20-branding
python3 tests/polish415_browser.py --output tests/results/v4.20-desktop
python3 tests/polish415_mobile_browser.py --output tests/results/v4.20-mobile
python3 tests/polish418_browser.py --output tests/results/v4.20-polish418
python3 tests/safari419_browser.py --output tests/results/v4.20-safari

LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18041 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=0
python3 tests/matchmaking_browser.py http://127.0.0.1:18041 \
  --output tests/results/v4.20-matchmaking

go test -run '^$' -bench 'Benchmark(EightBotsHuge35|RoomBroadcast35)$' -benchmem -count=1
go build -trimpath -o leqra .
```
