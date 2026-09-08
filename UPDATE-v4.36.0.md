# leqra v4.36.0

## Round results and countdowns

- Every game mode retains a two-second round-end hold. Survival loss and win, Capture the Flag and King of the Hill now show a compact result preview during the existing wait before the full results menu.
- Survival wave clears show a compact result, including the upcoming boss preview when relevant. The completed maze, defeated enemies and uncollected pickups stay visible for the full two-second hold, with pickup lifetimes frozen.
- At the next wave, Survival generates a new maze, revives the available squad, replaces enemies and pickups, and runs a full three-second countdown before combat. Elimination and wave retries also use three seconds (previously 2.6). Equipped power-up and spawn protection timers are frozen during countdown.
- Wave retries continue to preserve the current maze and completed-wave progress. New waves preserve the run's accumulated statistics.

## Stable lobby and player markers

- Elimination reserves the same objective-status row as the other modes, keeping the arena height stable when changing mode with the same map size.
- Sharing a local lobby publishes the complete rules and roster together. The client retains its preview and local pilot status panels during the handshake and initial lobby snapshot.
- Player 1 retains the gold spawn ring; local Player 2 uses neon pink, including reassigned online seats. The existing fade over the final 300 ms of actual spawn protection is retained.
- Every BACK TO action uses a left-side, left-facing arrow with centered button text.

## Remembered setup

Rules are remembered separately for Elimination, Survival, Capture the Flag and King of the Hill. Local roster settings include names, bot levels, team assignments, FFA colors, local Player 2 and spectating. Confirmed private host settings can be remembered; remote guests and matchmaking rosters are omitted. Existing saved rules migrate automatically, and invalid or unavailable browser storage falls back to a usable session.

Mode switches preserve the current map size and legal battle format. In the Rules menu, DEFAULT RULES loads the selected mode's default fields; APPLY RULES saves them. Map size, battle format and roster remain controlled by the lobby.

## Install

Replace the Go sources and the complete `web/` folder, then rebuild and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

The server, browser, versioned assets and offline cache use 4.36.0. Refresh clients after restarting. The application handshake prevents online play with an incompatible cached version.

See `TEST-NOTES-v4.36.0.md` for executed checks and limitations.
