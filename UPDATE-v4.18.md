# leqra v4.18 — results, rematches, browser guidance, and arena sizing

## Matchmaking match flow

Online matchmaking battles no longer show a **BACK TO MY PARTY** button in the active-match menu.
At match completion, queued participants instead receive two explicit result actions:

- **REMATCH** — neon green. Each network controller in the queued lineup votes once. The same
  hostless matchmaking battle restarts only when every participating controller has requested the
  rematch. A local Player 2 belongs to their controller and does not create a second vote.
- **BACK TO ROOM** — blue. This now performs the old private-party return transfer: the controller
  and their owned local Player 2 return to their reserved original room with its bots, rules,
  callsigns, teams and chat intact. Once anyone returns, the incomplete old battle cannot rematch.

Spectators can view the result but cannot request a queued rematch.

The result dialog is outcome-aware. A local winning side sees **VICTORY!**; a local losing side sees
**DEFEAT**; draws and neutral spectators see **MATCH RESULTS**. Losing clients are not congratulated.

## Ground pickup expiry

Uncollected power-ups now use:

`floor(maximum pickups × 8/3)` seconds

With the existing maze pickup caps, the six tiers expire after **13 / 18 / 32 / 45 / 61 / 90
seconds**. Giant (16×14) has 23 maximum pickups and therefore expires ground pickups after **61
seconds**. Ultra Wide (24×14) has 34 maximum pickups and expires them after **90 seconds**.

The Go server and local browser simulation use the same formula. Controls and Rules help derive the
shown value from the currently selected maze.

## Desktop browser recommendation

On a desktop non-Chromium browser such as Safari, leqra displays a small dismissible notice
recommending **Google Chrome** for the smoothest experience. Chromium-family desktop browsers do not
see it, and touch/mobile layouts suppress it. Dismissal lasts for the browser session.

## Arena sizing stability

Opening or closing the room/pause overlay and nested Controls dialog can change the arena's CSS box
as browser layout settles. v4.18 resizes immediately and once again on the next animation frame after
screen transitions. This keeps the canvas backing dimensions aligned with the final arena box and
prevents transient horizontal stretching.

## Controls and eliminated-state copy

With only Player 1 and the default aliases active, the desktop Field Manual now shows the arrow-key
movement row above the WASD row, with both accepted. Q / Space are likewise shown as alternative fire
controls.

A dead local Player 1 or Player 2 remains **TANK DOWN**. Their HUD cannot become **Spectating** merely
because both local tanks are eliminated; Spectating is reserved for an actual spectator role.

## Install

Replace all Go source files and the complete `web/` directory, then restart/rebuild the server:

```sh
cd leqra-online
go run .
```

Compiled and Docker deployments must rebuild because browser assets are embedded. Refresh connected
clients after upgrading. `/healthz`, `/api/config`, the Controls footer and `leqra.version` report
**4.18.0**.
