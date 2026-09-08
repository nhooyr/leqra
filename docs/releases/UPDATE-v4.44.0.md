# leqra v4.44.0

## Requested changes

- **Unshare room** and **Leave room** use their previous outlined style with the new neon purple and neon pink colors. PLAY retains its solid neon green appearance.
- **REMOVE/KICK** actions in room rosters, host controls and spectator lists use neon-red outlines. The kick confirmation action uses the same outline treatment; Cancel keeps its normal appearance.
- **Chat** uses the same blue as the Spectators header button. The unread border and count badge use that blue too.
- **Invite links open the join menu.** The room is prefilled and the callsign field receives focus. No connection begins until JOIN is clicked or Enter is pressed. This also applies when a recent session is available. After confirmation, a matching session can recover its seat and the selected callsign is applied to the resumed pilot. An expired session retains the existing new-seat fallback after confirmation; a token from a different room is never sent. Spectator invites retain their explicit START SPECTATING step. Ordinary background reconnection remains automatic.

The join action ignores duplicate submissions while connecting. Built-in server startup hints now use `go run ./src` to match the reorganized tree.

## Apply

Replace the server sources and complete browser assets, rebuild, restart and refresh clients. From the directory containing `go.mod`:

```sh
go build -trimpath -o bin/leqra ./src
./bin/leqra
```

Server, browser assets, PWA registration and offline cache all use 4.44.0. The root remains limited to README.md, CHANGELOG.md, MANIFEST.sha256, .gitignore and go.mod.

See [TEST-NOTES-v4.44.0.md](TEST-NOTES-v4.44.0.md) for verification. Native browser/device appearance remains unverified because the workspace browser policy blocks the game page.
