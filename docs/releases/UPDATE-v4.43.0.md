# leqra v4.43.0

## Maze stability and lobby actions

The arena now keeps its control and ammo-panel space when pilots switch between playing and spectating. The spectator action occupies Player 1’s reserved slot instead of adding another row. Player 2 keeps its slot when spectating, and narrow layouts reserve the existing two-pilot height when P2 is added or removed. Landscape control margins no longer depend on player role.

Removed obsolete five-plus-side header height overrides, which could enlarge the header when changing rosters or battle format. Opening a phone keyboard no longer triggers landscape controls merely because the visual viewport becomes shorter. Genuine viewport/orientation changes and selecting a different map size still refit the maze.

PLAY is neon green, Unshare room is neon purple, and Leave room is neon pink. The header Spectators action appears only in established online rooms; local role controls remain available in the lobby and pause menu.

## Online input fix

A delayed P1 or P2 packet could cross into the other pilot’s input channel after a seat swap. Its higher sequence number could then block the replacement pilot’s controls and apply an unwanted fire press. Current browser packets now include the stable member identity; the server validates it before accepting the sequence or fire edge. Existing ownership checks and legacy protocol-1 member-less packet behavior remain intact.

## Optimization

Room metadata broadcasts now use typed public records instead of per-field dynamic maps. The encoded packet remains byte-for-byte identical, including optional zero colors, false rematch votes, empty lists and party/queue state. The full-gallery benchmark improved from 105.873 to 15.336 microseconds per broadcast, approximately 6.9× faster, with allocations reduced from 869 to 7. This measures metadata preparation and enqueueing, not gameplay FPS or network delivery.

## Repository layout and upgrade

The root contains README.md, CHANGELOG.md, MANIFEST.sha256, .gitignore and go.mod. Go sources are under `src/`, browser assets under `src/web/`, tests and evidence under `src/tests/`, launchers under `scripts/`, deployment files under `deploy/`, and guides under `docs/`. Historical release reports are in `docs/releases/`.

Extract this reorganized release into a fresh directory to avoid retaining obsolete files from an older layout. From the directory containing `go.mod`:

```sh
go build -trimpath -o bin/leqra ./src
./bin/leqra
```

Windows: build `bin/leqra.exe` with the same `./src` package argument. Launchers are now `scripts/run.sh` and `scripts/run.bat`. Docker commands are `docker build -f deploy/Dockerfile -t leqra .` or `docker compose -f deploy/compose.yaml up --build -d`. Restart the server and refresh browsers; server, client and offline cache all use 4.43.0.

## Screenshot limitation

The current browser explicitly rejected the local game page under its URL security policy and prohibited alternate capture routes. A genuine browser screenshot could not be produced. `docs/screenshot.png` is unchanged from the previous staged production-Canvas render, and is not browser verification for this release. Native desktop/mobile appearance, including the new neon buttons and geometry, still needs a device retest.

See [TEST-NOTES-v4.43.0.md](TEST-NOTES-v4.43.0.md) for executed checks and their limits, and [the full guide](../README-verbose.md) for setup.
