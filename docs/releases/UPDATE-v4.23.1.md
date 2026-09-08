# leqra v4.23.1 — local/online UI cleanup and result emphasis

This patch fixes three presentation/state regressions reported after v4.23.0.

## Leave match is online-only again

The online pause menu still exposes **Leave match**, but the control is now explicitly hidden whenever the client transitions to local play. The local-room reset path clears it, `setScreen` defensively re-synchronizes it from the current mode, and the online-menu path refuses to mutate online-only controls unless the current mode is actually online.

This specifically fixes the sequence where an online match was played first and a later local game could inherit a visible **Leave match** action.

## Server shutdown warning is much more prominent

A `server_shutdown` packet still safely tears down the online session and returns the player to the local Home/room screen. It now also opens a blocking, accessible shutdown dialog with:

- a dimmed/blurred backdrop;
- large red **SERVER SHUTTING DOWN** heading;
- high-contrast warning icon and message;
- an explicit **YOU HAVE BEEN RETURNED TO THE HOME SCREEN** line;
- a focused acknowledgement button.

The existing room-status message and extended shutdown toast remain as secondary cues.

## Play Again matches Rematch

The normal **PLAY AGAIN** result action now uses the same neon-green `#39ff88` treatment as the matchmaking **REMATCH** action, including hover and disabled states.

## Upgrade

Replace the Go source and complete `web/` directory, then rebuild/restart. Browser assets now live under `/assets/v4.23.1/`, so the versioned-asset system naturally bypasses v4.23.0 caches.

```sh
go build -trimpath -o leqra .
./leqra
```

`/healthz`, `/api/config`, the browser API and Controls footer report **4.23.1**.
