# leqra player guide

## Controls

- **Player 1 on desktop** uses the mouse to aim and left-clicks or holds to fire. W/S drive forward and back. A/D steer and switch back to keyboard aiming until the pointer moves again. Q/C also fire.
- **Player 2** uses the arrow keys and Space/Enter. These keys also control Player 1 when Player 2 is inactive.
- **Touch** uses the joystick to drive and steer, and Fire to shoot. Press Fire again to detonate an active grenade.
- **P or Esc** opens the in-game menu. **M** toggles sound and **F** toggles fullscreen.

Open **Room settings → Controls** to remap keys, adjust audio, or replay the quick tour.

## Rooms

Press **Play** to start with bots. Open **Players and bots** to edit the roster or add Player 2. **Room settings** holds the mode, format, map, rules, and presets. **Portrait maze** makes rectangular maps taller than they are wide. The square Compact map keeps its dimensions.

**Share room online** opens the room to friends. Share the invite link or room code. Guests select **I'm Ready**, then the host starts the match. **Find online battle** opens public matchmaking. To watch a private room, use its spectator link.

## Game modes

| Mode | Goal |
| --- | --- |
| Elimination | Be the last tank or team standing. |
| Capture the Flag | Return the enemy flag while your flag is at base. |
| King of the Hill | Hold the hill to earn points. |
| Survival | Clear waves with your squad. |

Bank shots around corners and collect glowing pickups. Your own shots and grenade blasts leave your tank unharmed. [Power-up guide](POWERUPS.md)

## Local development

Run `./dev.sh` or `go run ./src` from the repository root. The server uses port 8080 by default. Open the root `index.html` directly for offline play.

The authoritative simulation and transport live in `src/`. The browser game lives in `src/web/`. Versioned browser paths symlink to their shared sources for local play. The Go binary embeds those sources directly and serves them at the same versioned URLs.

[Test commands](TESTING.md) · [WebSocket protocol](PROTOCOL.md) · [Release notes](releases/) · [Changelog](../CHANGELOG.md)
