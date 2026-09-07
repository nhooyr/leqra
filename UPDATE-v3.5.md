# leqra v3.5 — room chat, eight tanks, bigger maps and performance

## Online room chat

The speech-bubble button in the header opens **ROOM CHAT**, in the lobby or during
a match. Players and spectators use the same room-wide conversation. **Enter**
opens it when Enter is not assigned to a gameplay action. In the composer, Enter
sends and Escape closes. The header shows an unread count while chat is closed.

Messages show the sender's server-approved callsign and their role/team at the
time of sending. A secondary local player shares their device controller's chat
identity; the second tank's gameplay controls and callsign are still independent.
This is **everyone-in-the-room chat**, not a private/team channel. Spectators can
read it too. Room membership is required, and other rooms receive none of it.

Typing releases both local tanks' inputs; it **does not pause the online match**
or protect either tank. Close chat before returning to combat. The chat panel
floats over the game, rather than changing the arena's dimensions. On phones its
composer also follows visual-viewport changes to stay above an on-screen keyboard;
physical-keyboard/phone-browser behavior still needs real-device testing.

Each message supports **1–280 Unicode characters on one line**. The server accepts
a burst of four messages, then replenishes one message per second. That allowance
belongs to the member and cannot be refreshed by toggling spectating. Malformed,
empty/invisible-only, oversized, or too-fast messages receive an error. Message
content is displayed as plain text, never parsed as HTML or automatically made
into links. Names, membership and sender roles cannot be forged in the payload.

The room keeps its **last 60 messages** in memory. Joining/reconnecting receives
that history without duplicate rows. Starting another match keeps the same chat;
leaving one room and entering another clears the previous room from the panel.
Room expiry or a server restart removes the history. There is no account archive,
private messaging, team-only chat, permanent chat ban, or automated moderation.
Existing host kicks remove a chatting player/spectator and revoke their reconnect
session. As before, a kick is not a permanent identity ban.

## Eight tank seats

Rooms now support **up to eight tanks plus up to 16 spectators**. The eight tank
seats are shared by online humans, bots and the optional second local keyboard
player. The default roster remains you against two Normal bots; it does not
silently add five more opponents. There are still four numbered teams, or up to
eight independent opponents when the host enables Free-for-all.

Spawns use distinct perimeter cells. High-numbered seats participate in movement,
weapons, self-damage, team protection, scores, objectives, respawns, sudden death,
role swaps and reconnects. Eight-entry FFA score strips wrap on small screens.
The second local player still has their own name, controls and ammunition panel,
even when allocated seat seven rather than one of the original four indices.

A full eight-tank room admits the next ordinary visitor as a spectator, up to the
separate gallery limit. Spectators remain spectators between games. Hosts can
still kick and swap members, add bots, assign teams and control match rules.
Eight-seat setups can be shared and stored in room presets.

## Maps

**RULES & MODE → MAP SIZE** now offers:

| Map | Cells |
| --- | --- |
| Compact | 7 × 7 |
| Standard | 9 × 8 |
| **Large — new default** | **12 × 10** |
| **Huge — new option** | **14 × 12** |

New local rooms and newly created online rooms default to Large. Existing saved
presets retain a map they explicitly specify; loading an old Standard preset
still chooses 9 × 8. The host can choose any supported map between matches.

Maze dimensions continue to determine the laser's full-perimeter travel limit
and the homing missile's half-perimeter limit. Tank speed is unchanged. Fitting
a larger maze onto the same display makes each tank and its on-screen movement
smaller; that is a scale change, not slower movement in world coordinates.
Fullscreen and Hide Sidebar provide more display space, subject to the map's
aspect ratio; Compact remains available for small screens.

## FPS and graphics settings

Open **CONTROLS → PERFORMANCE**, either from the room or the in-match menu.

**Show FPS and frame time** adds a small, fixed overlay inside the arena. It
samples actual animation-frame intervals and updates approximately every 750 ms.
It shows rendering frames per second and average frame time, not the Go server's
simulation tick rate or snapshot rate. Hovering it also shows the worst recent
frame, measured JavaScript update/render submission time (excluding GPU execution),
and online round-trip latency when applicable. Background-tab intervals are reset.

**Performance graphics** limits canvas pixel density to 1×, reduces glow and uses
fewer cosmetic particles. The normal setting retains up to 2× pixel density.
Controls, tank speed, hitboxes, wall geometry, missile seeking, damage, scoring and
network simulation rates do not change. Both preferences are saved in this browser
when storage is available; they do not change anyone else's graphics settings.

At 60 FPS a frame is about 16.7 ms; at 30 FPS it is about 33.3 ms. Low rendering FPS
can be helped by Performance graphics. Healthy FPS with delayed or corrected
online movement points to a different path, such as network timing or server load;
the FPS counter is not a network-quality guarantee.

## What was optimized, and what was measured

There was avoidable work in the previous build; it was not fully optimized.
The changes in this release are:

- The HUD no longer rewrites unchanged labels each animation frame. Combat
  feedback updates at a bounded 30 Hz, and hot input/member lookups avoid building
  a decorated copy of the entire room roster. Rendering and physics keep their
  existing rates.
- Static maze walls have a spatial index in both Go and the browser. Rays and
  tank collisions narrow their checks to nearby walls. The original collision
  calculations and wall order are preserved, with a new query after a collision
  pushes a tank. Test-only exhaustive implementations check identical results.
- The server constructs and JSON-encodes a snapshot **once per room update**,
  instead of repeating that work for each player and spectator. Clients needing
  a new maze receive the full-world variant; ordinary pending updates remain
  replaceable, while map/room/chat delivery stays reliable. Each recipient still
  needs network bandwidth—this is not a compression or unlimited-capacity claim.
- Chat history is bounded and does not travel inside the 30 Hz movement snapshots.
  The core input-replay/interpolation module, `web/netcode.js`, is unchanged.

See **PERFORMANCE-v3.5.md** for the recorded before/after measurements, benchmark
commands and limitations. Both the old and updated four-tank browser profile
already ran at approximately 60 FPS on this test machine. Reduced work is useful
headroom; it does **not** establish that every device will gain a particular FPS
increase, nor that the user's exact source of choppiness was reproduced.

No claim is made that every path is optimal. Eight tanks, larger maps, many
projectiles, device/GPU limits, browser scheduling, network jitter and server load
remain relevant. The server is still a single process with in-memory rooms; its
configured room/player limits are not tested production-capacity guarantees.

## Install the update

Stop the existing server. Preserve custom deployment settings, then replace
**all Go source files and the entire `web/` folder**, including the new `chat.go`
and `spatial.go`. From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player's browser. `/healthz` and `leqra.version` report **3.5.0**.
Old clients assume four tank indices and must not be mixed with this server.
A restart removes online rooms, scores and chat. Browser-saved controls, presets,
sidebar and display preferences remain where storage is available.

Rebuild compiled servers because the browser assets are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can rebuild
with `docker compose up --build -d`, keeping their custom configuration. There are
no new game runtime dependencies, npm build steps, accounts or database migrations.
The Go server must still be reachable at your LAN/public address; this source
package is not a newly hosted public service.

## Verification

**Final checks:** 312 Go tests with the race detector (594 including subtests), 24 JavaScript networking tests, 52 live production WebSocket checks and 181 browser assertions passed. Both local players passed delayed-network role-change and reconnection checks. Go vet, syntax checks and compiled embedded-asset byte checks passed.

See **TESTING.md** and the version-labelled reports in `tests/results/` for the
checks actually run against this release. They include eight-seat admission and
input ownership, chat validation/history/isolation, cross-room/kick protection,
Unicode transport, map defaults, indexed-vs-exhaustive collision comparisons,
mobile chat bounds, FPS persistence, prior HUD/flag/victory/sudden-death behavior,
and two-local-player movement and reconnection under synthetic network delay.

Tests use Chromium desktop/mobile emulation, exact injected assets, synthetic
Location/History/storage adapters and real local Go WebSockets. Physical phones,
Safari/Firefox, public internet hosting, real packet loss, Docker execution and
production capacity were not tested. The on-screen keyboard viewport handler is
implemented but not a substitute for real mobile browser keyboard testing.
