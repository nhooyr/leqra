# leqra v4.11 — cleaner HUD, FFA presets, readable Shotgun and tank power badges

## Simpler Shotgun icon

The Shotgun pickup now uses a deliberately simple spread symbol: one horizontal motion line fans into three distinct lines to the right, with three small pellet endpoints. The small motion strokes behind it preserve a sense of speed without recreating a detailed firearm silhouette that becomes unreadable at pickup/legend size.

The same `powerIcon('scatter')` renderer is still shared by the maze pickup, sidebar legend and Rules & Mode picker, so the icon cannot drift between those locations.

## Under-arena controls strip

The Player 1 fire-key badge now reserves enough width for **Q / SPACE** and cannot flex-shrink into clipped text. The callsign uses the remaining space instead.

The offline **FIRST TO 5** micro-label beneath the arena has been removed. Match target information remains in the sidebar/score UI; online games may still use the same small right-side area for network latency. This frees horizontal room for loadouts on local games, especially phones and narrow windows.

## Local pause menu

The **New local room** action no longer appears in the pause menu of a running local match. The useful in-match actions remain:

- Back to the arena
- Restart match
- End match & edit room

Creating a fresh local room is still available from the room/setup screen, where it is much harder to trigger accidentally.

## New quick presets

Two built-in presets are added under **PRESETS**:

| Preset | Roster | Map | Format |
| --- | --- | --- | --- |
| **4-tank Free-for-all** | 1 human + 3 Normal bots | Large · 12×10 | FFA |
| **8-tank Free-for-all** | 1 human + 7 Normal bots | Huge · 14×12 | FFA |

These are built-in quick setups, not new saved-device slots. Loading one uses the existing preset validation and then becomes the current local-room configuration like the other built-ins.

## Active power-up icons on bots and remote online tanks

Bots in local matches and all non-local tanks in online matches now show compact active-power badges around the tank.

The first badge starts at the **top-right**, then the first four proceed clockwise through **bottom-right → bottom-left → top-left**. Additional simultaneous effects continue around the tank. The badges can show:

- the currently equipped timed weapon
- Shield
- Super Speed
- Scope
- Ghost

Local controlled tanks keep using the richer P1/P2 loadout panels instead of duplicating these badges. Shield rings and Speed streaks continue to show their stack intensity directly on the tank.

Badge artwork is cached once per power-up and reused. The render loop also reuses one scratch list when gathering active effects, so the extra status information does not allocate a fresh array for every bot/remote tank on every frame.

## Bug and optimization audit

This pass rechecked room setup, presets, local pause/resume/restart, underbar layout, power state rendering, projectile/pickup regressions, and the existing Go simulation suite.

No additional damage, scoring or elimination bug was found in this targeted pass. Two UI-state problems were addressed as part of the requested work:

1. the offline score-target text competed for horizontal space with the Q / SPACE key badge;
2. the local pause menu exposed a destructive **New local room** action next to ordinary pause controls.

Additional render cleanup in v4.11:

- cached mini power-up badges instead of redrawing their Canvas paths per frame;
- reused badge-kind scratch storage in the hot tank-render loop;
- offline HUD updates no longer rewrite a hidden/removed score-target string every refresh.

Physics, tank speed, weapon balance, network tick/snapshot rates, matchmaking and scoring rules are unchanged from v4.10.

## Install

Stop the current server, preserve custom deployment settings, and replace all Go sources plus the complete `web/` directory.

```sh
cd leqra-online
go run .
```

Refresh every player and spectator. Compiled deployments must rebuild because the executable embeds the browser assets:

```sh
go build -trimpath -o leqra .
./leqra
```

The server and browser report **4.11.0**. Restarting still clears in-memory online rooms, chat, scores and active matches; browser-local rules, presets, bindings and preferences remain where storage is available.
