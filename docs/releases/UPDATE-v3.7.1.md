# leqra v3.7.1 — CTF flags without captions

Removed the text and label backgrounds beneath Capture the Flag markers in
all three states: at home, dropped, and carried. The base-name captions beneath
the home markers are also removed, so no leftover base label remains under a flag.

The colored flag icons, team numbers on their pennants, base rings, and carrier
connecting lines remain. Flags still render behind tanks. Tank callsigns and the
objective status bar at the top are unchanged.

This is a visual-only patch. Capture/return rules, flag positions, spawn clearance,
weapons, scoring, post-match statistics, networking, and movement are unchanged.
The same renderer is used for local play, online players, and spectators.

## Install

Stop the existing server and keep your custom deployment settings. Replace the
project files with this package, then run from `leqra-online`:

```sh
go run .
```

Refresh each player's and spectator's browser. For a compiled deployment, rebuild
because the executable embeds the browser assets:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can use
`docker compose up --build -d`, preserving their deployment configuration.
The server and browser report **3.7.1**. Restarting clears in-memory rooms,
chat, and current match reports as before; browser-saved presets and controls
are not changed by this patch.

## Verification

The targeted browser checks cover home, dropped, and carried flags at 1365×950,
390×844, 320×568, and 844×390. They verify no flag/base captions or caption backing
strips, retained pennant numbers and objective HUD, unchanged objective data,
stable arena dimensions, and flags still behind tank hulls.

**Passed:** 85 focused browser assertions, 345 top-level Go tests with the race
detector (653 including subtests), and 24 JavaScript networking tests. JavaScript
syntax, Go vet, and compiled-server checks are documented in `TESTING.md`.

Browser tests used Chromium desktop/mobile emulation with the shipped assets and
synthetic Location/storage adapters, not physical phones or public hosting.
