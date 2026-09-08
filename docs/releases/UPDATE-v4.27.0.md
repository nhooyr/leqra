# leqra v4.27.0 — Co-op Survival and bolder bots

## Co-op Survival

Open **RULES & MODE → Co-op Survival**, or choose its preset for a human pilot and a Fierce teammate. The mode works locally and in shared online rooms, with one to four squad tanks. Combine human players, local Player 2 and friendly bots; at least one active human is required. All squad tanks share Team 1. Enemy tanks appear automatically and do not occupy roster places.

The default goal is **10 waves**, adjustable from 1–20. Each wave has a configurable timer, defaulting to **75 seconds**, and uses the same maze. It starts with two enemies, adds one every two waves and caps at four. Early waves use Chill/Normal bots; later waves use Fierce. Every fifth wave includes a **Godlike boss**. Bosses receive three shield charges, one speed stack and a rotating Homing/Cannon/Laser weapon only when the corresponding pickups are enabled. Turning pickups off removes starting boss gear too.

Clear the enemies together. A surviving friendly bot can finish a wave while human teammates are down. A four-second break clears hazards and pickups; squadmates return with fresh tanks, and pickups seed again for the next wave. Firing and movement are inactive during the break. Clearing the target wave count wins; a wipe, expired timer or departure of the last connected human ends the run. Mutual destruction is a loss.

The HUD shows the wave, enemies remaining and a living boss. Death feedback explains that the pilot returns next wave. Results report waves cleared and preserve squad statistics. Live visitors spectate until the run ends, and squad entries/swaps are locked during the run. Switching a room with more than four active tanks into Survival is rejected without removing anyone. Public matchmaking queues are unchanged.

## Power-up timing

| Map | Equipped weapon / buff duration | Uncollected pickup expiry |
| --- | ---: | ---: |
| Compact | 10 seconds | 30 seconds |
| Standard | 10 seconds | 30 seconds |
| Large | 10 seconds | 32 seconds |
| Huge | 15 seconds | 45 seconds |
| Giant | 15 seconds | 61 seconds |
| Ultra Wide | 15 seconds | 90 seconds |

The longer duration applies to equipped weapons and Shield, Speed, Scope and Ghost. Projectile ranges, projectile lifetimes and the **10-second grenade fuse** retain their independent limits. The uncollected expiry floor applies to Large and smaller mazes; Large already exceeded the floor.

A **Machine gun** now has a maximum of **five seconds of firing**, represented by 300 successful projectiles at its existing 60-round/second ceiling. You can pause and resume firing without using that budget, while the normal 10- or 15-second equip timer continues. A fresh Machine gun pickup restores the budget. The HUD shows firing time left alongside time available to use it, and online prediction accounts for shots awaiting server confirmation.

## Godlike and UI improvements

Godlike bots commit to useful routes and firing positions instead of repeatedly reversing near-equivalent choices. They advance when progress stalls, keep useful bank-shot plans between scans and tolerate lower-risk near misses when attacking. Immediate danger can still override a movement commitment. This gives co-op teammates more initiative without adding hull speed or invulnerability.

Threat selection is bounded to relevant nearby projectiles, and planning reuses its working buffers. This reduces repeated prediction work in projectile-heavy scenes. Godlike can also recognize an almost-depleted Machine gun when choosing a replacement pickup. These changes apply locally and on the server, including Survival enemies and bosses.

The Field Manual keeps the default **Q / C / Space / Enter** fire choices together on one line. Both players' remappable alternate fire keys, inactive-P2 fallback controls and game-styled confirmation dialogs are retained. New mode labels, squad limits, wave countdowns and results describe Survival directly rather than calling it a round-win or Hill match.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Rebuild an existing executable or Docker image: browser files are embedded in the server. A restart clears in-memory rooms and scores. Refresh every player's browser after restarting; the application-version handshake requires matching client and server versions.

The server, browser and service-worker cache use **4.27.0**, with the manifest and browser assets under **`/assets/v4.27.0/`**. Confirm `/healthz` and the browser report 4.27.0. Offline local play, installation as a PWA, prior Safari audio fixes, graceful shutdown notices and versioned cache updates remain supported.

See **TEST-NOTES-v4.27.0.md** for executed checks and their limits, **README.md** for setup and current gameplay, and **PROTOCOL.md** for the Survival state and machine-gun snapshot fields.
