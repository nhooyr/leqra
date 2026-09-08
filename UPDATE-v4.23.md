# leqra v4.23 — PWA, versioned assets, graceful shutdown, and online UX fixes

## 1. Installable PWA with real offline local play

The web app now ships a Web App Manifest, Android/Apple icons and a service worker. The service worker precaches the complete v4.23 application shell and uses a network-first navigation strategy with a cached Home Screen fallback. Versioned static assets are cache-first. Online endpoints are deliberately excluded from the cache.

Local startup performs **no WebSocket connection and no `/api/config` fetch**. The browser connects to `/ws` only when an online action is actually requested: Share Room Online, Join/invite/resume, or matchmaking. Opening `web/index.html` directly also remains a local-only path; PWA registration is skipped on `file:` URLs.

PWA/service-worker installation normally requires **HTTPS**. `localhost` is the development exception. On iPhone/iPad use Safari **Share → Add to Home Screen**; on Android use the browser's **Install app / Add to Home screen** action. Plain LAN HTTP can still run the game, but is not a reliable installable-PWA context on mobile browsers.

## 2. Versioned immutable browser assets

The Go server now serves only the HTML shell at `/` or `/index.html`. Every other browser asset is under:

```text
/assets/v4.23.0/
```

Examples:

```text
/assets/v4.23.0/theme.js
/assets/v4.23.0/game.js
/assets/v4.23.0/style.css
/assets/v4.23.0/manifest.webmanifest
/assets/v4.23.0/sw.js
```

`index.html` is sent with `Cache-Control: no-cache, must-revalidate`; versioned static assets use `Cache-Control: public, max-age=31536000, immutable`. Old root URLs such as `/game.js` and `/theme.js` now return 404. A new leqra release therefore changes the URL itself and bypasses stale browser/CDN asset caches.

The embedded production filesystem was also narrowed to `web/index.html` plus `web/assets`, so the standalone binary no longer embeds duplicate root developer copies of the JavaScript/CSS files.

## 3. Client/server version handshake before online play

Every WebSocket now begins with:

```json
{"type":"server_hello","version":"4.23.0","protocol":1}
```

A v4.23 client verifies both fields, replies with `client_hello`, and only then sends the original room/matchmaking request. The server refuses all ordinary commands from real WebSocket clients until that handshake succeeds. A mismatch returns `version_mismatch` plus the server version and an explicit instruction to reload the page.

This prevents a cached older page from silently speaking to a newer authoritative server with incompatible client behavior.

## 4. Graceful SIGTERM/SIGINT shutdown

Before the Go process closes its simulation and sockets it broadcasts:

```json
{"type":"server_shutdown","message":"The leqra server is shutting down. Returning to the Home Screen."}
```

Online browsers display the notice, explicitly leave the server-backed session, clear online state, and return to a fresh local Home Screen. This avoids intentional server maintenance looking like a normal network failure/reconnect loop.

## 5. Room and match behavior

- The obsolete **New local room** action is gone. Local play already starts in the local room; online lobbies retain their normal **Leave room** action.
- **Unshare room** now snapshots and restores the currently displayed maze/walls/pickups instead of generating a replacement preview. The roster, rules, bots, local Player 2 and room name continue to return to local ownership.
- The online in-match menu again includes **Leave match**. It also stays available on the reconnecting menu, including if the connection fails before the user has previously opened the pause menu.
- When a host changes the room format from Free-for-all to Teams, active tanks are distributed as evenly as possible across Team 1 and Team 2 (for example 2–2 with four tanks or 3–2 with five). Teams 3 and 4 remain available for subsequent manual assignment.
- Keeping chat open no longer disables the arena by itself. Input is suppressed while focus is inside the chat panel; click/tap/focus the arena and the match remains controllable with chat still visible.

## 6. Bug fixes and optimization audit

In addition to the requested behavior, the pass fixed an explicit `/index.html` redirect that was unnecessary for PWA shell precaching, and fixed the interrupted-connection **Leave match** visibility edge case noted above.

Concrete optimization/caching improvements include immutable version-addressed assets, old service-worker cache cleanup, avoiding online/API work during local startup, restoring the Unshare preview instead of regenerating a maze, encoding the shutdown notice once for broadcast, and excluding duplicate root web sources from the compiled embed. Existing v4.17–v4.22 simulation/rendering/network optimizations remain in place; this release does not claim a universal FPS or latency percentage improvement.

## Install / upgrade

Replace all Go source files and the complete `web/` directory, then rebuild because the browser shell/assets are embedded:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Or during development:

```sh
go run .
```

After deployment, load the site once while online so the new v4.23 service worker can install its shell. `/healthz`, `/api/config`, the Controls footer and `leqra.version` report **4.23.0**. Existing online rooms, queues, current scores and server chat are in-memory and reset on a server restart. Browser-saved controls, presets, callsigns and display preferences remain where browser storage is available.
