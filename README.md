# leqra v4.34.0

This update stabilizes the maze when pressing **GO**, ties golden player rings to spawn protection, tightens tank labels and icons, improves Host Controls and Survival retry styling, gives the squad starting shields on boss waves, and keeps the final impact visible before results.

See [UPDATE-v4.34.0.md](UPDATE-v4.34.0.md) for changes and upgrade commands and [TEST-NOTES-v4.34.0.md](TEST-NOTES-v4.34.0.md) for verification. Earlier versioned guides remain available as release history.

## PWA and online lifecycle

leqra is an installable Progressive Web App with fully local play. The served page includes a manifest, Apple/Android icons and a root-scoped service worker. The app shell is cached for offline startup, while `/ws`, `/api/*` and `/healthz` remain network-only. Opening the game locally does not create a WebSocket or fetch online configuration; the browser connects only when a player explicitly shares/joins an online room, follows an online invite/resume, or starts matchmaking.

The static deployment is now version-safe. `index.html` is always revalidated, and every other browser asset served by Go lives under **`/assets/v4.34.0/`** and is sent with an immutable one-year cache policy. A future release therefore gets a new asset URL instead of waiting for an old JavaScript/CSS cache entry to expire. The service worker follows the same versioned shell and removes older `leqra-app-*` caches after activation.

Online connections now begin with an explicit page/server compatibility handshake. The server sends its application version and wire protocol before accepting room or matchmaking commands; the client confirms both before continuing. A stale or incompatible page receives a clear **reload the page to update** message instead of attempting to play against mismatched code.

Graceful shutdown is now visible to players. On SIGTERM/SIGINT the Go process queues a **server shutting down** message before closing connected sockets. Browsers that are currently online show the notice, leave the server-backed game, and return to the local Home Screen instead of sitting in a reconnect loop against a server that is intentionally stopping.

Retained room/game polish includes the **Leave match** action in the online pause menu, removal of the obsolete **New local room** action, preservation of the current maze when a host Unshares a room, even distribution across all four teams in Elimination/Hill (the first two for Capture the Flag) when Teams is activated, and gameplay input while chat remains visible as long as focus is outside the chat panel. A reconnect audit also fixed Leave match remaining hidden on the interrupted-connection screen before the menu had previously been opened.

The Safari audio fixes, game-styled confirmations and remappable alternate fire keys from v4.26 are retained. See **UPDATE-v4.26.0.md** for that release and its physical-device testing limits; the current changes and verification are in **UPDATE-v4.34.0.md** and **TEST-NOTES-v4.34.0.md**.

The v4.15 lobby behavior still keeps editing from replacing the maze. Renaming, recoloring,
adding/removing pilots, changing bot difficulty, team-format edits, and other non-map
room changes refresh the roster without generating new walls; changing **Map Size** is
the lobby action that deliberately generates a new preview maze. The new **Ultra Wide**
size is **24×14**.

Start-of-round control hints and power-up pickup explanations now use each local pilot's
reserved status line beside the ammo display instead of the top-of-arena toast. P1 and
local P2 have independent feedback, and the fixed-height status area does not grow when
messages appear. Focus loss clears held input but never pauses the game; pause remains
an explicit player action. Spectator-facing copy consistently uses **Spectators** and
**Spectating**.

Uncollected pickup lifetime now scales with the maze's maximum pickup count using
`floor(maximum pickups × 8/3)`, with a **30-second minimum on Large and smaller maps**. Giant is therefore **23 max / 61 seconds** and
Ultra Wide is **34 max / 90 seconds**. The Controls menu shows starting pickups, maximum
pickups, and this expiry duration for the selected maze.

Player 1 fires with **Q / C** by default; Player 2 uses **Space / Enter**. Both fire keys are remappable in Controls. When Player 2 is inactive, all of their current movement and fire bindings also control Player 1, even after either player remaps keys. All twelve bindings remain unique, and existing saved remaps are preserved.

**Machine gun rounds are shooter-safe and travel one total quarter-perimeter path**
(`(maze width + maze height) / 2`), counting the hidden muzzle section and every ricochet.
The stream remains continuous at up to 60 authoritative rounds/second with a 96-round
per-owner active cap. Each machine-gun pickup provides **180 successfully fired rounds**, equivalent to **three seconds of continuous firing at 60 rounds/second**. Pausing fire preserves the remaining firing budget while the regular 10- or 15-second equip timer continues. Each pilot’s ammo display shows **FIRE LEFT**, the remaining time against its **3-second total**, and a live depletion bar. The weapon label marks the independent equip timer as **EXPIRES**. **Grenades have a 10-second fuse and
a 220-unit blast radius**. They keep most of their launch speed through the first seven seconds, then brake progressively harder as detonation approaches. Godlike bots predict grenade blasts, remote detonation danger and expiring fuses as well as the grenade body. They also predict homing turns, seek useful power-ups and prioritize objectives. Godlike now commits to routes and firing positions for longer, advances when progress stalls, and avoids abandoning useful movement for low-risk near misses. Expensive forecasts select a bounded set of relevant projectiles and reuse planning buffers.

The match-complete popup adds **PLAY AGAIN** beside Back to Room. Local matches restart
immediately with the same room/rules; online guests use the same button to ready for the
next match and the host can start as soon as everyone is ready. Local pause menus now
also include **Restart match**. The Laser icon was redrawn as a clear beam/emitter so it
cannot be confused with Shotgun.

The dark-only neon-blue theme, authoritative team colors, self-owned FFA paint,
five-stack Speed/Shields, objectives, spectators, matchmaking, chat and post-match
statistics remain intact. See **UPDATE-v4.34.0.md** for current behavior and installation and **TEST-NOTES-v4.34.0.md** for current verification. Older weapon guides describe the releases named in their headings; the power-up table below gives current timing.

## Previous combat improvements (retained)

The Fire/cooldown HUD now has one update path and stable completed-round states.
Online firing adds immediate local cosmetic feedback, server-tagged volley
reconciliation, sound deduplication and continuous projectile presentation.
Remote turning continues through short snapshot gaps instead of stopping and
snapping ahead. Online cosmetic work and unchanged HUD/input updates are reduced.

Go still owns all damage, ammunition, cooldowns, scoring and game rules. Local feedback is
not a promise of zero-latency server-confirmed online hits. See **UPDATE-v4.2.md**
for behavior and installation, and **TEST-NOTES-v4.2.md** for measurements and limits.

**Cannon now fires 4×-diameter, 4×-speed rounds** through internal walls and
ricochets them off the arena rim. **Ghost** lets tanks phase through internal
walls for the map-dependent 10- or 15-second duration and stacks with Super Speed, Shield, Scope and weapons.
Bots can now be removed with one click; human kicks still require confirmation.
See **POWERUPS.md** and the retained **UPDATE-v4.1.md** for weapon and expiry rules.

**FIND ONLINE BATTLE** now queues solo pilots or your private-room party against
random compatible people connected to the same Go server. Choose Elimination
1v1 / 2v2 / 3v3, Capture the Flag 3v3, King of the Hill 3v3, or eight-player
Free-for-all on the 16×14 maze.

Up to **three real active players** can queue as a party, including local Player 2.
Remote friends confirm the search individually. A party never splits across teams;
solos can fill open team positions. FFA is solo-entry. Bots remain in the private
room and never fill matchmaking slots. A full lineup starts automatically.

The original lobby is reserved. On matchmaking results, **BACK TO ROOM** restores it,
including names, bots, teams, rules and chat. **REMATCH** requests another battle with
the same queued lineup; the hostless public battle restarts only after every participating
network controller requests it. Source spectators can spectate through its match link.
Public battle rules and team assignments cannot be changed by a player-host. Private-room
hosting remains available outside matchmaking.

See **UPDATE-v4.0.md** for queue sizes, fixed rules, consent, cancellation, return,
reconnection and deployment boundaries. **TESTING.md** lists current executions;
older version-labelled reports and update guides are retained as history.

This is a source package, not an already-hosted matchmaking service. Everyone
must use the same reachable Go server. It needs enough real players in a
compatible queue before forming a match; there is no automatic bot backfill.

## v4.13 desktop layout

Normal desktop now uses the same compact shell as fullscreen: the hero/footer/status slogan no longer reserve space, and the arena can use the full viewport. This minimizes maze resizing when fullscreen is toggled.

## v4.14 controls, score strip, and local round restart

Press **F** to enter or leave fullscreen; F is reserved from gameplay bindings. The summary score strip above the maze is always visible, including with the desktop sidebar open, and remains one line for up to eight sides. In paused local Elimination games, **Restart round** now rebuilds only the current round while preserving the match score and round number.

## Start playing

From this extracted folder, with Go 1.23 or newer installed:

```sh
go run .
```

Open **http://localhost:8080**. The game opens directly into your local room,
with you plus three Normal bots. A fresh desktop setup uses Free-for-all on a 12×10 map; phones start with Compact, and saved room rules are restored. Press **START MATCH** or change the roster.
Local play works without a WebSocket connection; `web/index.html` can also be
opened directly for local-only play.

### Install on iPhone / Android

For the installable PWA, serve leqra from **HTTPS** in a normal deployment. `localhost`
is treated as a secure development context, but a plain `http://192.168.x.x` LAN URL can
play the game without necessarily being eligible for service-worker/PWA installation.
On iPhone/iPad, open the HTTPS site in Safari and use **Share → Add to Home Screen**.
On Android, Chrome/compatible browsers offer **Install app** or **Add to Home screen**.
After the current app shell has been installed/cached, the installed app can launch without a
network connection and local matches remain playable. Online rooms and matchmaking still
require a reachable Go server and naturally cannot work while offline.

**+ LOCAL PLAYER 2** adds a second tank using arrows + Space / Enter by default on the
same device. Player 1 uses WASD + Q / C. The Controls menu edits both layouts; inactive Player 2 bindings fall back to Player 1. **F toggles fullscreen.** On a phone, the primary player uses
the thumbstick and Fire button. Player 2 needs a keyboard on that device.

Press **+ ADD BOT** to copy the last bot’s difficulty in roster order; the first bot defaults to Normal. Change any existing bot with its
Chill / Normal / Fierce / Godlike selector. THE LINEUP shows each bot's level beside its name, including bots on mixed teams. In Teams Elimination or Hill, assign each participant to one of four numbered teams; Capture the Flag uses the first two, and Survival puts the whole squad on Team 1. Rename them
in RULES. Free-for-all is a room-wide host format, not an individual team option. Numbered teammates share round points and cannot hurt each other unless the host
enables friendly fire;
default first side to five wins in Elimination and 30 points in King of the Hill. Elimination, Capture the Flag and Hill require at least two opposing sides; Survival requires one to four available squad tanks, including an all-bot squad.
Choose Elimination, Capture the Flag, King of the Hill or Survival using the home-screen icon selector. Tap an icon, or focus the selector and use arrows, Home or End. Choose **Teams / Free-for-all** directly beneath it, then **map size** beneath the format. Capture the Flag and Survival use fixed Teams format. Open **RULES** to change the score target, timer, weapon availability, pickup rate or friendly fire. The lobby action reads **GO**, with centered text; **PLAY AGAIN** belongs to the results screen. The selected mode stays colored on touch devices, and the rules summary wraps between complete items without a leading dot on a new line. **F** toggles fullscreen inside menus when text entry, select typeahead or key remapping is not using it. Active matches suppress pinch zoom throughout the page, including pause menus; single-finger scrolling and joystick + Fire input are retained.
A tied objective time limit enters sudden death: one final life, last side wins. Only the host
can change the battle format or teams. Global Free-for-all hides the per-tank team selectors entirely. Survival also hides them because squad membership is fixed.

**SHARE ROOM ONLINE** publishes your configured local roster to the Go server.
It retains the bot settings, local player and teams, updates the address bar,
and enables **COPY INVITE LINK**. Opening that link directly joins the room.
The host starts; connected active guests ready up first. Bots and the secondary local
player are automatically ready. Spectators need not ready up. Full arenas admit new
people as spectators; remove a bot or use a host swap to make a tank place. Survival runs admit new visitors as spectators and lock squad entries/swaps until the run ends. Sharing
is done in the lobby, not halfway through a round. **COPY SPECTATOR LINK** invites
spectators with a callsign prompt; **SPECTATE / JOIN AS PLAYER** changes your own role.

Go is required on the hosting computer only. `run.bat` (Windows) or `sh run.sh`
(macOS/Linux) starts the same server. For a phone, open the printed **Same Wi-Fi**
address rather than localhost. A server accessible only on your home Wi-Fi is
not reachable by friends elsewhere. Public play needs a publicly reachable Go
server, usually behind HTTPS. The Share button is not a hosting deployment.

## Survival

Choose **Survival on the home-screen icon selector**, or load the **Survival** preset for a human pilot and a Fierce teammate. Play alone, with local Player 2, with online friends, or with friendly bots. The squad has **one to four tanks**, all on Team 1; an all-bot squad can play while the host spectates. Switching an oversized room to Survival is rejected until you reduce the active roster; it never silently removes players.

The default run has **15 waves**, with a configurable target of **1–20** and a **75-second timer per wave** by default. Each wave starts with two enemies, plus one every two waves, capped at four. Every fifth wave replaces one enemy with a boss. Each higher AI level first appears as a boss before joining ordinary waves:

| Waves | Regular enemies | Final wave boss |
| --- | --- | --- |
| 1–5 | Chill | Wave 5: Normal |
| 6–10 | Normal | Wave 10: Fierce |
| 11–15 | Fierce | Wave 15: Godlike |
| 16–20 | Godlike | Wave 20: Godlike |

Normal bosses start with one shield charge and no speed boost; Fierce bosses get two shield charges and one speed stack; Godlike bosses get three and one. Bosses also receive an enabled Homing/Cannon/Laser weapon selected in rotation. Boss equipment respects disabled pickups. On boss waves, each active squad tank starts with at least one shield charge, including on a wave retry; this squad bonus applies even when shield pickups are disabled. The bonus uses the regular shield duration (10 seconds, or 15 seconds on Huge maps and larger). Before a boss wave, the four-second intermission previews the next wave, its actual boss difficulty and enabled equipment. THE LINEUP includes every squad member and enemy on a separate row, with AI levels and explicit boss markers. Defeated enemies remain listed during the break until the next wave replaces them.

Clear the enemies before time runs out. One surviving squad tank can complete a wave for everyone; fallen squadmates return after a four-second break, with fresh tanks. The maze stays the same throughout the run. Bullets and uncollected pickups clear between waves; pickups seed again with the next wave. Fire and movement are inactive during the break. A squad wipe or expired timer ends the run, and mutual destruction counts as a loss. Each cleared wave adds one shared point; surviving the target wave count wins.

Choose **RESTART WAVE** on a lost Survival result, or **Restart wave** in its pause menu, to retry the current wave. Completed-wave progress and the maze are preserved. Available squad tanks revive with fresh equipment, enemies and the timer reset, and a countdown gives everyone time to locate their tank. The retried wave's statistics are discarded; earlier completed-wave statistics remain. The results action is neon purple and reads **RESTART WAVE**. **PLAY AGAIN** starts a new run from wave 1. In online rooms only the host can restart a wave; active-wave confirmation uses the game UI. Completed waves are not restarted during the intermission, and changing the run setup invalidates its old checkpoint.

Survival and objective endings leave the arena visible for 500 ms before showing results. The simulation and statistics finalize immediately while the last impact effects finish. Elimination retains its existing, longer round-end hold.

Golden circles identify local Player 1 and Player 2 while their spawn protection is active, including countdowns and Survival wave spawns. The circle ends with spawn protection. Remote players, bots and spectators do not receive another player's locator circle. Tank labels stay fixed above the hull, including at the top maze edge, and do not move as power-ups change; bot/remote power-up icons wrap clockwise around the lower half of the tank.

Enemy tanks are generated automatically and never occupy room-player places. New online visitors spectate during a run; squad entries and swaps wait until it ends. Disconnecting removes the current life, with recovery possible at a later wave after reconnecting while the run continues. Available bot teammates can continue after human pilots leave or spectate; an empty or defeated squad cannot continue. Survival is available in private rooms and local play; public matchmaking queues are unchanged.

## Weapons and room features retained

Homing missiles now turn at **4.8 radians/second**, acquire across a wider cone
and up to ten cells away, and recover their lock sooner. They still ricochet
and can travel at most **half the maze perimeter**. They are deliberately harder
to dodge; cover remains useful.

The unified room includes per-bot difficulty, host-only teams and roster controls,
a second local controller that works online too, and server-simulated bots.
Host kicking, in-room callsign edits, arbitrary Unicode room names, direct
join-or-create invites, and multiplayer smoothing remain supported.

See **GAMEPLAY-v3.2.md** for the rules and objectives introduced in that version and **UNIFIED-ROOMS.md** for the unified-room behavior, controls, safety rules,
reconnection/ownership details and upgrade instructions. Earlier release guides
are retained as historical notes; current behavior is described in this README and UPDATE-v4.34.0.md, with the retained
room/objective/spectator features in their versioned guides.

## Power-ups

All ten pickups use the **same icon drawing** in the legend and maze.
Lasers bounce for up to the full perimeter. Homing missiles bounce for up to
half the perimeter. Grenades detonate on tank impact or a ten-second fuse:
throw, release Fire, then press Fire again to trigger an early blast. Their blast radius is 220 world units. Equipped weapons and timed buffs last **10 seconds on Compact, Standard and Large**, or **15 seconds on Huge, Giant and Ultra Wide**. Projectile lifetimes, range limits and the grenade fuse keep their own limits. Machine gun, Shotgun and stacked shields remain available. Teammate hits do not consume shields with friendly fire off. Ordinary returning shells, missiles and grenade blasts can hurt their owner; **Machine gun, Shotgun and Laser are shooter-safe**. Cannon rounds pass through internal walls, bounce
at the rim and last at most 5.3 seconds. Ghost lets tanks cross internal walls for
the map-dependent duration, stacks with speed, and safely clears a wall overlap on expiry.
See **POWERUPS.md**.

Scope is independent of weapons, speed and shields. Its timer refreshes to the map-dependent duration
when collected again; it never stacks extra range or damage. Both local
pilots see their own extended guide and a separate `SCP` timer.

| Map | Cells | Starting pickups | Uncollected cap | Pickup expiry | Equipped/buff duration |
| --- | ---: | ---: | ---: | ---: | ---: |
| Compact | 7×7 | 2 | 5 | 30 s | 10 s |
| Standard | 9×8 | 3 | 7 | 30 s | 10 s |
| Large (default) | 12×10 | 4 | 12 | 32 s | 10 s |
| Huge | 14×12 | 5 | 17 | 45 s | 15 s |
| Giant | 16×14 | 6 | 23 | 61 s | 15 s |
| Ultra Wide | 24×14 | 7 | 34 | 90 s | 15 s |

Extra spawn attempts remain one live second after start, then every 1–2 seconds
by default. The host can change frequency or disable any/all of the ten types.
Safe placement and the area cap remain; uncollected pickup lifetime is derived from the
maze cap as `floor(cap × 8/3)` seconds, raised to at least 30 seconds on Large and smaller maps. A cap is a maximum, not a promise that every
arena will always fill to it.

## Updating from an earlier version

Back up custom deployment settings. Replace **all Go sources and all of `web/`**,
restart the server, and refresh every player's browser. Rebuild executables or
Docker images because they embed the web files. In-memory rooms and scores reset
on restart. Both the health endpoint and browser version should show **4.34.0**.

## Build one standalone server

```sh
go build -trimpath -o leqra .
./leqra
```

On Windows:

```powershell
go build -trimpath -o leqra.exe .
.\leqra.exe
```

The executable embeds `web/`, so it can run without separate assets. **Rebuild it after changing the web files.** The ZIP intentionally contains source rather than unsigned prebuilt executables.

Use a different port:

```sh
go run . -addr :9090
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `PORT` | `8080` | Port, used unless `ADDR` or `-addr` overrides it |
| `ADDR` / `-addr` | `:8080` | Listen address; `:PORT` accepts LAN connections |
| `MAX_ROOMS` / `-max-rooms` | `64` | In-memory room limit; range 1–512 |
| `ALLOWED_ORIGINS` | Empty | Optional comma-separated exact browser origins, including scheme; never `*` |

`GET /healthz` reports health, version, and room count. `GET /api/config` reports protocol version and rates. `GET /ws` is the WebSocket upgrade endpoint.

## Let friends play over the internet

**This package is not a live hosted service.** For players outside your Wi-Fi, run the Go app on a publicly reachable server and share that server's HTTPS URL. A static-only hosting service cannot run this backend.

Run a **single instance** of the app and put a TLS reverse proxy in front of it. The included `deploy/Caddyfile` is a minimal example for a machine with a domain name pointed at it:

```sh
# On the server, with the app built and Caddy installed:
./leqra -addr 127.0.0.1:8080
# In another terminal, after editing game.example.com in deploy/Caddyfile:
caddy run --config deploy/Caddyfile
```

Use a process supervisor for both processes in an actual deployment. Configure DNS and permit the reverse proxy's public HTTP/HTTPS ports. Keep the backend's port private. The browser automatically uses WSS when the page is served over HTTPS. Caddy's reverse proxy supports WebSocket upgrades; retain the public Host header and do not strip the Origin header. With the included same-host configuration, no `ALLOWED_ORIGINS` setting is necessary.

Official reverse proxy documentation: https://caddyserver.com/docs/caddyfile/directives/reverse_proxy

Alternatively, build and run the supplied Docker image:

```sh
docker build -t leqra-online .
docker run --rm -p 8080:8080 leqra-online
# Or:
docker compose up --build
```

The provided Compose file exposes plain HTTP for local use. For public hosting, place it behind HTTPS and restrict direct access to the app port. The Docker image runs a static binary as an unprivileged user. Docker/Caddy examples are included, but were not exercised against a public host in the delivered test run.

Official Docker multi-stage build documentation: https://docs.docker.com/build/building/multi-stage/

## Architecture

`matchmaking.go` runs consented human-only queues and preserves original private lobbies. It creates separate fixed-rule battle rooms, then uses the existing game engine.

`game.go` owns the online simulation, with `bots.go` providing per-bot AI and `roster.go` validating room setup: movement, collision detection, bounces, damage, cooldowns, ammunition, power-ups, rounds, and scores. It advances at **60 simulation ticks/second**. `hub.go` sends **30 state snapshots/second** and sends the maze when a new generation starts or a client reconnects.

The browser sends **controls, never trusted coordinates or hit reports**. It predicts its own tank at the same 60 Hz movement step as Go, uses the server's sequence **and held-input step count** to replay only unacknowledged movement, and smooths visual correction offsets separately from physics. Sub-tick rendering supports higher refresh rates. Remote tanks use a continuous server-tick playback buffer with an adaptive 70–180 ms target; packet arrivals no longer restart interpolation. Short, wall-constrained extrapolation bridges small gaps. The server keeps at most one pending replaceable snapshot per client; map-bearing snapshots remain reliable. Visual particles and audio remain client-side. All clients share authoritative outcomes. This is not a claim of comprehensive anti-cheat: automation, information disclosure inherent in full-world snapshots, and denial-of-service are separate concerns.

`transport.go` is a small, dependency-free, text-only RFC 6455 server transport. It supports browser masking, fragmented UTF-8 text, interleaved ping/pong, and close frames. It negotiates no extensions or compression. It is isolated from the game so it can be replaced independently. The included tests cover malformed frames and live interoperability, but this custom implementation has not received an independent security audit or a full Autobahn conformance run.

`main.go` serves the embedded client, checks request origins, limits connections, and shuts down on interrupt/SIGTERM. Inputs are bounded and stale controls become neutral after 350 ms. Message sizes, rates, write queues, and room counts are bounded. Reconnect credentials are sent only to their owner, stored in that tab's session storage, and never placed in invite URLs or broadcast state.

RFC reference: https://www.rfc-editor.org/rfc/rfc6455

## Deployment boundaries

Rooms and scores are **in memory** and disappear when the process restarts. Room chat and same-server random matchmaking are included. There are no accounts, skill ratings, persistent rankings, cross-server pools, or global hosting service. Queues, active matches and return reservations also disappear on restart. Empty rooms expire after disconnect grace; inactive rooms expire after 30 minutes. Rooms are not synchronized across processes: simply adding replicas behind a load balancer will not create a shared room service.

The room limit is a resource cap, **not a tested capacity guarantee**. Load-test your host before raising it. There are coarse per-socket-IP connection budgets (120 new attempts/minute and 256 concurrent connections) and per-client message limits. The backend deliberately does not trust `X-Forwarded-For`. If all traffic comes from a reverse proxy, its socket IP shares these budgets. Apply real-client-IP rate limits and abuse controls at the trusted edge for public use, monitor CPU/memory/latency, and keep the Go toolchain and operating system patched. Server authority does not make a public game immune to cheating or abuse.

## Tests and source map

```sh
go test -race ./...
go vet ./...
```

See **TESTING.md** for the actual checks performed, optional live WebSocket/browser scripts, and test limitations. **PROTOCOL.md** describes messages and state ownership.

```
main.go          HTTP server, embedded assets, configuration
transport.go     Bounded WebSocket framing and handshake
hub.go           Rooms, sessions, validation, broadcasts
matchmaking.go   Party consent, six queues, exact team packing and room transfers
game.go          Authoritative online tank simulation
survival.go      Cooperative waves, boss loadouts and squad lifecycle
bots.go          Server-controlled bot navigation, aiming and evasion
roster.go        Host-only roster setup, sharing and team rules
teams.go         Validated Unicode team names and rule copying
web/             Canvas game, offline AI, online client, responsive controls
web/netcode.js   Testable prediction/reconciliation and snapshot playback math
*_test.go        Unit, simulation, security, and transport tests
tests/           Optional live protocol and browser integration tests
deploy/          Reverse proxy example
```
