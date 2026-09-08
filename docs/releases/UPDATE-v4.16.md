# leqra v4.16 — lowercase full-game rebrand

## Brand and product name

The game is now **leqra** everywhere players and operators normally encounter the product. The wordmark is intentionally lowercase. Browser metadata, the Controls version footer, server startup output, README/current docs, archive/project directory, executable name, Docker examples, and public browser API now use `leqra`.

The landing hero now says **ENTER leqra.** instead of using the previous product name as a slogan. Ordinary gameplay language such as “ricochet,” “ricochets,” and “ricocheting” remains unchanged where it describes bouncing projectiles rather than the product.

## Browser API and saved settings

The canonical browser API is now `window.leqra`; `leqra.version` reports **4.16.0**. The internal browser helpers are `leqraNet` and `leqraTheme`.

New browser persistence uses the `leqra.*` namespace. On first load, v4.16 copies existing settings/session values from the former namespace when a corresponding `leqra.*` value does not already exist. This preserves names, controls, preferences, presets, local room rules, and reconnect state during the rename without continuing to write new data under the old brand.

## Server and deployment naming

The Go module is `leqra`. The recommended compiled binary is `leqra` (`leqra.exe` on Windows), the Docker image examples use `leqra-online`, and the server banner says `leqra online`. Development fixture environment variables use the `LEQRA_` prefix.

The WebSocket ping payload was also renamed to `leqra`; it remains an opaque ping payload and does not change game protocol semantics.

## Gameplay compatibility

This is a branding release. v4.15 gameplay rules, Ultra Wide 24×14, power-up lifetime scaling, spectator wording, fixed-height per-pilot HUD feedback, explicit-only pausing, lobby maze preservation, and victory-score coloring are unchanged.

## Install

Replace the Go source and complete `web/` directory, then restart:

```sh
cd leqra-online
go run .
```

For a compiled binary:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh all clients after the server restart because browser assets are embedded in compiled builds.
