# leqra v4.38.0

## Requested UI changes

- Removed “Updates on Enter or when you leave the field.” beneath the shared room name. The existing Enter/blur save behavior remains available.
- Local Player 1's starting circle is neon purple (`#bf5cff`). Player 2 remains neon pink. Both still follow the actual spawn-protection timer and ease out over its final 300 ms; online reassigned seats retain their proper local-player colors.

## Countdown tips

Ordinary three-second countdowns show one short tip that stays stable throughout the countdown and pause/resume. Tips vary across rounds, waves, retries and rematches, mixing the current mode's rules, enabled power-ups and general mechanics.

Survival has extra guidance about wave timers, fallen squadmates, the last survivor, fresh mazes/equipment, wave retries, all-bot squads and boss-wave rules. Other modes cover elimination wins/draws, flag captures/returns and hill scoring/contesting. Numeric tips reflect configured targets, respawn delays and map-dependent power-up durations. Disabled pickups do not produce power-up tips.

Boss countdowns continue to show only their boss difficulty and equipment, preserving the earlier preview request and keeping the three-second display readable. Completed-wave previews contain neither the next boss's details nor countdown tips.

## Bug fixes

- A browser that denies access to `localStorage` or `sessionStorage` no longer aborts startup before defaults can load. Access to each storage object is guarded independently, so an available store can still migrate its legacy settings. Existing saved values take precedence over migrated values.
- An interrupted Unshare request no longer leaves Unshare permanently disabled after reconnecting or joining another room. Connection loss and leaving clear the old request and its saved snapshot. Late callbacks from an older socket cannot clear a newer request.
- In online Capture the Flag and King of the Hill, a fire tap pressed and released while dead can no longer produce a phantom shot on the revival tick. The server now discards that prior-life fire edge from its sampled input. Currently held fire/movement, fresh new-life taps and other living pilots' quick taps remain responsive, including local P2.

## HUD optimization

Player loadout and combat-feedback displays now collect occupied ammo, live grenades, fuse time and hostile missile locks in one projectile pass per pilot per display function. A full two-pilot refresh uses four passes instead of ten, a **60% reduction in projectile reads**, while avoiding temporary filtered arrays. There is no persistent cache to become stale after firing, death, team changes or new online snapshots.

At 192 projectiles, median HUD processing time in the Node fixture decreased from 8.522 to 7.323 microseconds locally (14%) and from 9.706 to 8.244 microseconds online (15%). These measurements exclude browser layout, painting and simulation; they are not FPS or phone-performance claims. See `PERFORMANCE-v4.38.0.md` for the complete fixture, stress results and raw evidence.

## Install

Replace the Go sources and the complete `web/` folder, then rebuild and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh clients afterward. Server, browser, versioned assets and offline cache use **4.38.0**. The existing handshake requires matching client and server versions for online play.

See `TEST-NOTES-v4.38.0.md` for executed checks and remaining verification limits. Earlier broader UI restructuring proposals remain unimplemented.
