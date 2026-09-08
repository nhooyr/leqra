# leqra v4.22 — current verification

Current verification is documented in **TEST-NOTES-v4.22.md**. The release specifically adds regression coverage for the served Safari `blob:` audio policy, stronger Safari gesture activation, integrated matchmaking chat, Ghost cross-wall overlap behavior, automatic callsign/room-code editing, Join-only room navigation, and host Unshare.

Representative commands from the extracted source tree:

```sh
go test -race ./...
go vet ./...
go build -trimpath -o /tmp/leqra-v4.22 .
node --check web/theme.js
node --check web/netcode.js
node --check web/game.js
node --test tests/*.test.cjs
python3 tests/polish421_browser.py --output tests/results/v4.22-audio
python3 tests/safari419_browser.py --output tests/results/v4.22-safari
python3 tests/polish422_browser.py --output tests/results/v4.22-polish
python3 tests/polish418_browser.py --output tests/results/v4.22-polish418
```

The optional real-WebSocket browser fixture and production matchmaking protocol harness remain available for end-to-end queue/chat/rematch/reconnect checks; see the versioned test notes for what completed in the final run.

A native Safari/WebKit runtime is not installed in this build environment. The Safari suite runs the shipped WebKit/iOS detection, CSS, touch, sizing, native-audio fallback and delayed-Web-Audio paths under Safari/iPhone/iPad identities in system Chromium. The server test separately verifies the CSP needed by real Safari's generated `blob:` WAV fallback. Physical Safari on macOS/iPhone/iPad remains the final listening/performance acceptance target.
