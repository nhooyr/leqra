# leqra v4.34.0 — steadier transitions and clearer tank status

## Maze and menus

Pressing **GO** keeps the maze's playing dimensions. Ammo, objective and touch-control rows retain their layout space while hidden in menus; the menu overlay spans the full area available below the arena title. This prevents the canvas from shrinking when those controls appear. Canvas bitmap resizing happens at the start of drawing, so a resize callback cannot leave a blank bitmap between frames. The round and HUD initialize before the lobby overlay closes.

In Host Controls, LOCAL P2's **SPECTATE** and **REMOVE** actions share one line. Elimination's lobby summary now says **FIRST TO 5 WINS**, following the configured target. The Survival results action is neon purple and reads **RESTART WAVE**, without a wave number.

## Player markers and tank labels

The previous gold locator used its own timer and could outlast actual spawn protection. Gold now follows the local player's spawn protection and disappears when that protection ends. Player 1 and Player 2 are handled independently.

Tank labels remain fixed above the tank at the top maze edge instead of flipping underneath it. Labels can draw into the existing margin above the maze. Power-up icons use a closer clockwise arrangement while leaving room for the hull and label.

## Survival boss waves

Every active allied tank starts each boss wave with at least one shield charge, including human players, local Player 2, bots and all-bot squads. The bonus also applies when restarting a boss wave. It does not replace a stronger live shield or revive a disconnected/dead tank.

This is a squad starting bonus, so it applies even when shield pickups are disabled. It lasts the regular shield duration: 10 seconds through Large, or 15 seconds on Huge and larger. Ordinary waves retain their existing starting equipment; boss equipment still respects enabled pickups.

## Final-impact visibility

Survival and objective endings leave the arena visible for **500 ms** before presenting results. The outcome and statistics finalize immediately while the impact effects finish. Stale result presentation is canceled when leaving, restarting or changing online match generation. Elimination keeps its existing 2.7-second round-end hold, which already provides time to see the finish.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh browsers so client and server both report **4.34.0**.

Browser assets and the PWA cache use **`/assets/v4.34.0/`**. Framing protocol remains **1**. See [TEST-NOTES-v4.34.0.md](TEST-NOTES-v4.34.0.md) for executed checks and verification limits.
