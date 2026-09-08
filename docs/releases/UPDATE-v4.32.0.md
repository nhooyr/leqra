# leqra v4.32.0 — consistent controls and stable tank labels

## Dropdowns and Leave Match

Native dropdown controls share one down-chevron icon, a consistent inset from the right edge and room between the selected text and arrow. This includes the lobby Battle Format and Map Size controls, roster settings, Rules, Presets and spectator swaps. The platform's differing one-/two-triangle arrows no longer determine the closed control's appearance. Native keyboard and selection behavior are retained.

The compact color picker's invisible select no longer inherits oversized arrow padding that can extend its clickable area over a neighboring control. Leave Match menu and confirmation button text is centered.

## Survival

New Survival mode selections and the built-in Survival preset default to **15 waves**, reaching the first Godlike boss. Existing custom/saved targets remain valid. The wave schedule and four-second intermissions are unchanged:

- Waves 1–5: Chill enemies; Normal boss at 5.
- Waves 6–10: Normal enemies; Fierce boss at 10.
- Waves 11–15: Fierce enemies; Godlike boss at 15.
- Waves 16–20 remain available through Rules, with Godlike regular enemies and a boss at 20.

## Tank labels and power-up icons

Tank names keep the same position as effects are collected, stacked, consumed or expire. Bot and remote-player power-up icons progress clockwise over the lower half of the tank: right, lower-right, bottom, lower-left, then left. This keeps their starting position below the name label, preserves space around the hull, and avoids moving names to accommodate equipment.

Local controlled pilots continue to use their individual ammo/loadout HUD. Cached icon sprites are retained.

## Other bug fixes and optimization

Survival keeps **PAUSED** visible when paused during a wave or between waves. The HUD computes its final mode-specific labels before updating the page, avoiding repeated replacement of unchanged round, wave, timer and objective text. Sudden-death labels take precedence directly instead of overwriting ordinary objective labels on every refresh.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh players' browsers so client and server both report **4.32.0**.

Browser assets, PWA registration and the service-worker cache use **`/assets/v4.32.0/`**. Wire protocol remains **1**. See [TEST-NOTES-v4.32.0.md](TEST-NOTES-v4.32.0.md) for executed checks and verification limits.
