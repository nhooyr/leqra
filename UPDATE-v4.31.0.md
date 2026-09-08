# leqra v4.31.0 — Survival pacing and lobby controls

## Survival fixes

The last impact's screen shake now decays on the results screen instead of repeatedly jiggling the maze after a loss. The finished simulation remains frozen. This also lets residual shake settle while paused or back in the menu.

Defeated enemies stay in THE LINEUP throughout the four-second break, marked as defeated. The next wave replaces them when it spawns, avoiding the sidebar's disappearance and reappearance between waves.

Survival accepts squads of one to four available tanks, including all-bot squads with a spectating host. Bots can continue after human pilots leave or spectate, revive between waves, and finish the run. Empty or unavailable squads still cannot start or advance. Existing online host and readiness checks remain in force.

## Easier difficulty progression

Every stronger level first appears as a boss, then joins ordinary waves afterward:

| Waves | Regular enemies | Boss |
| --- | --- | --- |
| 1–5 | Chill | Normal on wave 5 |
| 6–10 | Normal | Fierce on wave 10 |
| 11–15 | Fierce | Godlike on wave 15 |
| 16–20 | Godlike | Godlike on wave 20 |

Normal bosses have one starting shield charge and no speed boost. Fierce bosses have two shield charges and one speed stack; Godlike bosses have three and one. Gear respects the enabled pickups, and Homing/Cannon/Laser weapon rotation is retained. Boss previews, names and status text show the actual difficulty and equipment. The default run remains ten waves.

## Lobby and tank status

- Battle format moves out of Rules and directly below Game Mode. Map size follows beneath it.
- Capture the Flag and Survival retain their fixed Teams format. Online settings keep host-only permissions and wait for server confirmation.
- King of the Hill now defaults to **30 points** in the mode selector, built-in preset and public Hill queue. Saved/custom targets are preserved.
- The lobby action always reads **START BUTTON**, including after returning from a completed match. **PLAY AGAIN** is reserved for the results screen.
- Bot and remote-player power-up icons form a row below the name label and clear of the tank hull. Placement accounts for maze edges and uses the existing cached icon sprites.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh players' browsers so client and server both report **4.31.0**.

Browser assets, PWA registration and the service-worker cache use **`/assets/v4.31.0/`**. Wire protocol remains **1**. No new client-supplied simulation fields are introduced.

See [TEST-NOTES-v4.31.0.md](TEST-NOTES-v4.31.0.md) for executed checks and verification limits.
