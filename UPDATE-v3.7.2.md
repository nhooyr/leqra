# leqra v3.7.2 — warning sound and Super fast pickups

## Missile-lock warning sound is on by default

New or unset device preferences now enable the existing missile-lock warning
sound automatically. This applies to both locally controlled pilots in local
and online matches; each warning still follows an actual lock on that pilot.

The setting remains under **CONTROLS → COMBAT FEEDBACK → Missile-lock warning
sound**. Turning it off is still saved on that device. An existing explicit
saved off choice is respected, as is the game's global mute. Missing, unreadable
or blocked storage falls back to the new on default. Other feedback, graphics,
FPS and key-binding preferences are unchanged.

## Super fast power-up frequency is the default

**RULES & MODE → POWER-UP FREQUENCY** now includes:

| Setting | Interval between extra spawn attempts |
| --- | --- |
| **Super fast — default** | **1–2 seconds** |
| Fast | 2–3.5 seconds |
| Normal | 4–6 seconds |
| Slow | 7–10 seconds |
| Off | No pickups |

With Super fast selected, a round starts with the existing **two pickups**.
The first additional spawn is attempted **one second into live play**, then
at randomized 1–2-second intervals. Countdown and local-pause time do not advance
this schedule. The same timing is used by the local simulation and Go server,
including objective games and a sudden-death reset.

The **five-uncollected-pickup cap**, enabled-power-up selection, safe placement
and 19-second pickup lifetime are unchanged. A full arena or unavailable safe
location can skip a spawn attempt rather than exceeding the cap.

New local rooms, new online rooms and the five built-in presets use Super fast.
Sharing a configured room carries its selected frequency to the server. Custom
presets can save and restore the new option; older presets keep their explicitly
saved Fast, Normal, Slow or Off choice. The host can change the frequency between
matches, and guests/spectators cannot override it. Compact phone settings show
the complete interval label on its own row.

This patch does not rebalance missiles, weapons, damage, scoring, objectives,
post-match statistics or movement. CTF flag captions remain removed. The core
network prediction/interpolation module is unchanged.

## Install

Stop the existing server, preserve custom deployment settings, and replace
**all Go sources and the entire web/ folder**. From the extracted project:

```sh
cd leqra-online
go run .
```

Refresh every player’s and spectator’s browser. The server's `/healthz` and
`leqra.version` should both report **3.7.2**. Do not mix older clients/servers
with this build: older rule validators do not recognize `superfast`.

For a compiled server, rebuild because the browser files are embedded:

```sh
go build -trimpath -o leqra .
./leqra
```

On Windows use `leqra.exe`. Existing Docker Compose deployments can use
`docker compose up --build -d`, retaining their deployment configuration.
Restarting clears existing online rooms, scores, chat and reports; browser-saved
controls, presets and explicit device preferences remain where storage is available.

## Verification

See **TESTING.md** and `tests/results/*v3.7.2*` for the checks performed. They cover
new and saved defaults, native browser audio scheduling with mute/off suppression,
all five frequency choices, local and Go spawn timing in all three modes,
sudden-death/new-round resets, caps and disabled weapons, host authorization,
preset persistence, live authoritative pickup delivery and spectator reconnection.

Browser checks use Chromium desktop/mobile emulation with the shipped assets,
synthetic URL/storage adapters and deterministic local simulation stepping. Live
network checks use the normal Go HTTP/WebSocket handler on loopback. Physical
phones, physical speaker output, Safari/Firefox and public hosting were not tested.
