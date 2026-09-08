# leqra v4.42.0

## Lobby

**PLAY** now appears directly above **FIND ONLINE BATTLE**, below the existing **Join another room** link. The same centered primary button, click handler, local/online start behavior and host permissions are retained. Results continue to use **PLAY AGAIN**.

## Bug fixes

Online Capture the Flag and King of the Hill respawns could stop held controls one tick after revival, until another input packet arrived. The server was clearing the current input record after already sampling it for the revival tick; this also reset the tank's input acknowledgement to zero. Respawning now preserves current controls and their sequence while clearing an obsolete queued fire press. Fresh releases, stale-message rejection and the normal input timeout still work for both primary and local Player 2.

Online pilot HUDs could retain expired power-ups between snapshots even though the tank's visible badges had expired. Both HUD paths and the tank renderer now share the same visual equipment expiry logic. Current weapon types, ammunition and stacks still come from the newest server state; visual copies age their timers without modifying snapshots or prediction state.

Survival intermissions no longer advance the pilot HUD's cooldown/respawn display or apply old speculative machine-gun consumption. Equipment and cooldown displays freeze during the break; live firing feedback resumes during active play. Countdown, pause and completed-round equipment timers also stay fixed.

## Optimization

Reopening or replacing chat history now creates one timestamp formatter for the batch rather than repeatedly setting up locale formatting for every message. Empty histories skip it; each fresh batch and each live appended message still follows current device locale/timezone settings. Timestamp text, message order, channel labels and scrolling behavior are preserved.

A 120-message history render measured **6.395 ms before and 0.843 ms after** (about **7.6× faster**) in a Node fixture executing the production rendering functions with native date formatting and a lightweight DOM. This excludes browser layout, painting and game simulation; it is not a game-FPS or physical-device measurement. Method and raw evidence are under `tests/results/v4.42.0/chat-performance.md`.

## Install

Replace the Go sources and complete `web/` folder, then rebuild and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh clients afterward. The server, browser, versioned assets and offline cache use **4.42.0**. Online client and server versions must match.

See `TEST-NOTES-v4.42.0.md` for current validation and limitations. Earlier gameplay, audio, high-resolution icons and mobile interaction protections are retained.
