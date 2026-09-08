# leqra v4.45.0

## Changes

- **Leave room** now uses the same neon-red outline as REMOVE/KICK.
- **New tanks appear at the bottom of the roster.** The reported insertion above Player 1 was real: a new bot or local Player 2 could reuse a lower combat seat number, which previously controlled row order. Rows now follow stable membership order in local and online rooms, host controls and the lineup. Existing input fields and unsaved edits remain intact.
- **Add Bot follows the last roster bot's difficulty**, including when that bot reused an earlier seat. Saved setups, presets, sharing and unsharing retain the same roster order.
- **Valid saved sessions reconnect automatically**, including when opening an invite. The server retains the existing callsign and player/spectator role. Fresh visitors still choose their callsign and press JOIN; fresh spectator invites retain START SPECTATING.
- **Expired or kicked memberships require explicit JOIN again.** If a disconnected player misses the existing 20-second recovery window, or the host removes them, opening an invite cannot silently create a replacement membership. Rejected recovery returns to the join menu. A callsign alone cannot authenticate recovery.

## Apply

Replace the server sources and complete browser assets, rebuild, restart and refresh clients. From the directory containing `go.mod`:

```sh
go build -trimpath -o bin/leqra ./src
./bin/leqra
```

Server, browser, PWA registration and offline cache use 4.45.0. The five root files remain README.md, CHANGELOG.md, MANIFEST.sha256, .gitignore and go.mod.

See [TEST-NOTES-v4.45.0.md](TEST-NOTES-v4.45.0.md) for verification and limitations.
