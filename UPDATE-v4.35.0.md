# leqra v4.35.0 — consistent holds and reliable online controls

## Two-second round ends

All game modes now use a **two-second round-end hold**. Elimination uses it before the next round or final results. Survival uses it between waves and at the end of a run, with the next-boss preview retained during the between-wave hold. Capture the Flag and King of the Hill use it before final results.

The client does not add another hold after an Elimination round has already waited on the server. Joining an already-finished match still opens its results immediately. Start countdowns remain 2.6 seconds. Outcomes and statistics stop changing once finalized, while impact effects can finish before results cover the arena.

## Online start/end stability

Online lobby snapshots intentionally contain no tank bodies. Previously this hid the assigned pilots' ammo panels and collapsed their height. Starting a match then expanded those panels again, which resized the maze despite the reserved HUD area introduced in v4.34.

HUD slots now follow room assignments, retaining their dimensions through empty lobby snapshots, GO and End Match. Their live contents use the newest server tank state before rendered bodies catch up. P1/P2 and spectator combinations retain the appropriate slots. Canvas bitmap resizing still happens together with drawing.

## End Match and Leave Match

Callsign autosave feedback keeps its layout space, so a blur-triggered save cannot move an action between pressing and releasing it. End/Leave confirmations remain valid across ordinary round and countdown transitions while continuing to validate the room, connection and player identity.

Confirmed lifecycle commands are not dropped behind the movement-message backpressure threshold. End Match tracks its pending request until the server acknowledges it or reports an error, preventing duplicate submissions and silent send failures. Results also wait for an open End/Leave decision or pending End acknowledgement, even after the round-end hold has elapsed. Server room and host restrictions remain enforced.

## Clearer notices and rules

Version mismatches display a prominent colored game notice with a reload action. Attempting to choose Survival with more than four tanks produces an immediate, prominent explanation instead of relying on text below the visible portion of the lobby. It does not remove tanks automatically.

Elimination's Rules label is **ROUNDS TO WIN**.

## Protection-ring fade

The gold local-player locator and grey protection circle share a smooth fade over the final **300 ms** of actual protection. Both reach zero exactly at expiry. Countdown and local pause freeze the fade along with protection; no extra invulnerability or separate cosmetic timer is introduced. Shield-hit grace does not bring the gold locator back.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh browsers so client and server both report **4.35.0**.

Browser assets and the PWA cache use **`/assets/v4.35.0/`**. Framing protocol remains **1**. See [TEST-NOTES-v4.35.0.md](TEST-NOTES-v4.35.0.md) for executed checks and verification limits.
