# leqra v4.21 test notes

## Final automated verification

Release validation completed with:

- **470** race-enabled top-level Go tests passed;
- **873** passing Go test/subtest events;
- **0** Go failures and **2** intentionally opt-in fixture skips;
- **56/56** JavaScript/Node tests;
- **7/7** focused v4.21 Safari-audio/volume browser checks;
- **87/87** real-Go-WebSocket matchmaking/browser checks;
- **128/128** real matchmaking protocol checks;
- **23/23** Safari/WebKit identity-path checks;
- **12/12** branding/storage-migration checks;
- **16/16** retained desktop gameplay/HUD checks;
- **6/6** narrow-mobile checks;
- **8/8** retained presentation/layout checks;
- `go vet ./...`, JavaScript syntax checks, and `go build -trimpath` passed.

The v4.21 audio test uses a deliberately delayed fake `AudioContext` resume transition. It proves that a sound requested while the context is suspended is queued and starts only after the asynchronous resume completes; it also verifies the 50% default, midpoint snap, persisted volume, and master-gain mapping.

The real matchmaking browser run covers explicit Party/Enemy labels, party-only delivery, enemy-only delivery, non-leakage to the other scope, separate drafts while switching channels, minimized-chat notification dispatch, local/mobile UI, reconnects, results/rematches, and return-to-room behavior. No uncaught browser errors occurred.

The real protocol run covers the same server boundaries without trusting browser UI: a matched party message reaches a travelling party member but not the opposing side or unrelated match spectator, and enemy messages retain their server-authoritative side filtering.

## Bugs fixed by the audit

1. **Safari async-resume race:** v4.20 could request `AudioContext.resume()` and immediately discard a tone because the context was not yet `running`.
2. **Wrong active chat state:** the client helper defaulted to `room` rather than `roomChat.channel`, so an open opponent panel could render/use room state.
3. **Matchmaking room-chat leakage:** the normal channel was still broadcast to the whole temporary battle room. It is now source-party-only during matchmaking.
4. **Shared P1/P2 duplicate delivery:** normal chat could send the same event twice to one WebSocket when both local pilots shared the connection. Both chat broadcasters now deduplicate sockets.
5. **Cross-channel draft/ack confusion:** the two panels shared one input without per-channel draft/pending ownership. Drafts and send acknowledgement are now channel-specific.
6. **Reconnect scope:** matchmaking normal-chat history is filtered by the same party relationship as live delivery.

## Safari limitation

Native Safari/WebKit is not installed in this build environment. The retained Safari suite exercises the shipped WebKit/iOS detection, CSS, touch, sizing, and fallback paths under Safari identities in system Chromium. The v4.21 audio regression uses a delayed Web Audio state machine to reproduce Safari's asynchronous resume behavior, but it is not a native macOS/iPhone/iPad Safari acceptance run. Physical Safari remains the final platform check.

## Commands

```sh
go test -race -count=1 -json ./...
go vet ./...
node --check web/theme.js
node --check web/netcode.js
node --check web/game.js
node --test tests/*.test.cjs
python3 tests/polish421_browser.py --output tests/results/v4.21-audio
python3 tests/safari419_browser.py --output tests/results/v4.21-safari
python3 tests/branding417_browser.py --output tests/results/v4.21-branding
python3 tests/polish415_browser.py --output tests/results/v4.21-desktop
python3 tests/polish415_mobile_browser.py --output tests/results/v4.21-mobile
python3 tests/polish418_browser.py --output tests/results/v4.21-polish418

LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18041 \
  go test -run '^TestBrowserFixture$' -count=1 -timeout=0
python3 tests/matchmaking_browser.py http://127.0.0.1:18041 \
  --output tests/results/v4.21-matchmaking
python3 tests/matchmaking_protocol.py http://127.0.0.1:18041 \
  --output tests/results/v4.21-matchmaking-protocol.json \
  --expect-version 4.21.0

go build -trimpath -o leqra .
```
