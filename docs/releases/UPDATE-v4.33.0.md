# leqra v4.33.0 — wave retries and clearer match controls

## Lobby and menus

The lobby action reads **GO**. Primary blue button labels center independently of their decorative arrows, including **BACK TO THE ARENA**, Join, queue and result actions.

**ADD BOT** copies the last bot's difficulty in roster order, with Normal as the first-bot default. The separate new-bot difficulty dropdown is removed. Individual bot difficulty selectors remain. Online additions resolve the difficulty on the server after any preceding roster edits.

Host Controls use compact, readable identity rows with callsign and team/difficulty information beside their actions. Human-readable Chill and Fierce names replace internal EASY/HARD values. Callsign forms have explicit separation from the host roster. Empty layout columns left behind by removed callsign Save and Join actions are removed. Narrow-screen Rules, Controls, Presets and Results layouts receive spacing/wrapping adjustments.

## Retry a Survival wave

Lost-run results offer **RESTART WAVE** alongside **PLAY AGAIN**. The Survival pause menu also offers **Restart wave** during the current wave or countdown.

A retry keeps the maze and completed-wave progress, revives the available squad, restores the current enemy/boss wave and timer, and starts a fresh countdown. Statistics return to the start-of-wave checkpoint so a discarded attempt cannot inflate kills, deaths or elapsed time. A full Play Again starts from wave 1.

Online wave restarts belong to the host, including a spectating host directing an all-bot squad. Restarting an active online wave uses a game-styled confirmation. Stale/duplicate requests, other game modes, won runs and between-wave breaks are rejected. Setup changes invalidate old checkpoints. Repeated losses can show fresh results and be retried again.

## Find your tank

Golden circles highlight actual local Player 1 and Player 2 throughout the initial countdown and briefly after play begins. They also appear on Survival wave starts and retries. They are visual locators and do not add protection or change gameplay.

Tank names sit closer to the hull while remaining fixed as effects change. Power-up badges use a tighter clockwise lower arc and a modest size reduction at low zoom, retaining readable icons and edge handling.

## Other fixes and optimization

- Corrected remote rotation extrapolation with stacked Speed boosts, reducing incorrect turn prediction and subsequent corrections.
- Removed temporary shot-preview arrays and used early-exit pending-shot checks in the online presentation ledger.
- Cached roster status nodes so unchanged room broadcasts do not repeatedly query each row's DOM.
- Fixed spectating hosts being unable to use Play Again for all-bot squads.
- Fresh retry generations close stale online menus and reset prediction/result state without regenerating the maze.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh browsers so client and server both report **4.33.0**.

Browser assets and PWA cache use **`/assets/v4.33.0/`**. Framing protocol remains **1**; the versioned client and server must be upgraded together for `restart_wave`. See [TEST-NOTES-v4.33.0.md](TEST-NOTES-v4.33.0.md) for executed checks and verification limits.
