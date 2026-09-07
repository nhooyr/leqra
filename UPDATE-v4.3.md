# leqra v4.3 — neon themes and automatic light mode

## Dark: neon green. Light: neon purple.

The dark interface now uses **neon green (#39FF14)** instead of the previous
lime-green primary accent. The new light interface uses **neon purple (#A100FF)**,
with white/lavender surfaces, dark text, and a matching pale maze. Small purple
text uses a darker variant for readability; primary buttons retain the neon color.

The themes cover the room, buttons, dialogs, rules, matchmaking, chat, results,
scoreboard, ammunition panels, touch controls, and the actual Canvas arena. Native
form controls and the browser's theme-color metadata follow the selected appearance.
Flags still render behind tanks without captions, as in the previous release.

Team identities and the ten power-up colors/icons remain consistent across both
skins. A player does not become a different team when someone changes appearance.
Small colored text is darkened in the light interface, while light-arena shots gain
a contrasting outline. Neither adjustment changes projectile size or collision.

## Choose Auto, Dark, or Light

From the room, open **CONTROLS → APPEARANCE → Color theme**. During a match, open
the room menu, then **Settings & controls → APPEARANCE**.

| Setting | Behavior |
| --- | --- |
| **Auto — default** | Follows the light/dark preference reported by the browser, including changes while the game is open. |
| **Dark · neon green** | Keeps the dark skin regardless of the browser preference. |
| **Light · neon purple** | Keeps the light skin regardless of the browser preference. |

A manual choice takes effect immediately and is remembered in that browser.
Selecting Auto resumes following the browser preference. This is a device-local
setting available to players and spectators; it does not require host permission,
change room rules, or alter anyone else's appearance. Browser-saved room presets,
key bindings, audio preferences, graphics settings and sidebar choices are untouched.

The separate preference key is `leqra.theme.v1`. Missing or invalid stored values
use Auto. When storage is blocked, the selection still works for the session and
the settings panel explicitly reports that it could not be saved. Clearing browser
storage resets the preference. Same-origin tabs receive storage-change updates.

The theme bootstrap loads before the styles so the initial page can select the
proper skin without deliberately rendering the old default first. Auto uses the
browser's `prefers-color-scheme` media query; this generally reflects browser or
operating-system appearance settings. It is not a time-of-day/location schedule.

## Presentation only: gameplay stays the same

Switching skins redraws the cached maze artwork once when the effective palette
changes. It does not regenerate the maze, change canvas dimensions, restart the
round, clear held inputs, reconnect the socket, or reset movement/shot prediction.
There is no per-frame style inspection or new polling loop for appearance.

The v4.2 stable end-of-round cooldowns, immediate local shot previews and smoother
projectile presentation remain included. Team colors, weapon behavior, movement,
hitboxes, bots, damage, objectives, scoring, statistics and matchmaking rules are
not rebalanced. `web/netcode.js` is byte-for-byte unchanged from v4.2. Production
Go files other than `main.go` are also unchanged; that file updates the version and
allows the two new appearance assets through the existing static-file handler.
The strict same-origin script policy has not been weakened.

This release does not introduce WebGL or claim a measured FPS/latency improvement.

## Install

Stop the existing server, preserve custom deployment settings, and replace the
project sources and **the entire web/ directory**, including the new `theme.js`
and `theme.css`. From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. `/healthz` and `leqra.version`
should report **4.3.0**. For a compiled deployment, rebuild because the executable
embeds all browser assets:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can use
`docker compose up --build -d`, keeping their custom deployment configuration.
Restarting clears online rooms, queues, current scores, chat and match reports;
browser-saved preferences and presets remain. There are no new game runtime
libraries, npm steps, accounts or database migrations. This is an updated source
package, not an already-hosted public game service.

## Verification

**Passed:** 421 top-level Go tests with the race detector (815 including subtests),
56 JavaScript tests, and 146 browser assertions: 105 appearance/room checks plus
41 existing online-firing/cooldown/reconnection checks. Go vet, JavaScript syntax
checks and a compiled-server embedded-asset comparison also passed.

The appearance checks cover both native Chromium color-scheme preferences,
live preference changes, explicit overrides, saved/invalid/blocked storage,
legacy media listeners, native form colors, and different skins in the same room.
They exercise 1365×950, 390×844, 320×568 and 844×390 viewports. All ten legend icons
still match their maze geometry. Theme changes preserve arena dimensions, game
state, held controls, the online connection and prediction history; completed-match
cooldowns remain stable. A live host, local Player 2 and spectator exercised room
chat and reconnection across different skins. The existing firing regression uses
injected delay and checks prediction/confirmation without claiming a new latency gain.

The two opt-in long-running/fixture-generation Go tests are skipped in the normal
suite and are not counted as passes. Old version-labelled results are historical,
not silently re-counted as current runs. Current reports and commands are under
**TESTING.md** and **tests/results/v4.3/**.

**Limits:** browser tests use Chromium desktop/mobile emulation, exact injected
assets, synthetic Location/History/storage adapters, and real loopback Go sockets.
The light/dark media query changes use native browser emulation; storage events
are additionally covered with synthetic unit tests. Physical phones, Safari/Firefox,
real-device first-paint behavior, native cross-tab storage, public internet hosting,
Docker execution and production hosting capacity were not tested. Physical device
preferences and display quality can differ from the emulated layouts.

Implementation reference: MDN, prefers-color-scheme:
https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-color-scheme
