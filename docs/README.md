# leqra player guide

## Controls

- **Player 1 on desktop** uses the mouse to aim and left-clicks or holds to fire. W/S drive forward and back. A/D steer and switch back to keyboard aiming until the pointer moves again. Q/C also fire.
- **Player 2** uses the arrow keys and Space/Enter. These keys also control Player 1 when Player 2 is inactive.
- **Touch** uses the joystick to drive and steer, and Fire to shoot. Push the stick further for a faster wide turn. Press Fire again to detonate an active grenade.
- **P or Esc** opens the in-game menu. **M** toggles sound and **F** toggles fullscreen.

Open **Room settings → Controls** to remap keys, adjust audio, or replay the quick tour.

## Rooms

The **Infinity** switch is on by default. Press **Play** to roam a public endless maze with up to 32 player tanks and 24 roaming bots. All ten power-ups can spawn. One unprotected hit destroys a tank. You gain a point for each tank you destroy and lose a point each time you die. Tanks respawn after one second, and the leaderboard shows the ten highest current scores.

Select **Infinity** under **Room settings → Game mode** to use your own roster. Up to eight tanks can occupy roster seats, including local Player 2 and configured bots. In **Rules**, you can enable additional roaming bots and choose their difficulty. Set a positive score target to play to a win, or leave it at zero for endless exploration. Use **Share Infinity room** to invite friends to the arena. Guests ready up and the host presses **Play**.

To enter public Infinity with an online room, the host enables **Infinity**, guests ready up, and the host presses **Play**. Everyone competes individually, with consistent tank colors. The sidebar keeps room members visible below the top ten when needed. The whole party must fit the public arena. Successful entry clears configured room bots; public roaming bots spawn independently.

New rooms start with Player 1 only. Turn off **Infinity** to play the selected room mode; if there are no bots, Player 2, or other online players in combat seats, three Normal bots join automatically. Open **Players and bots** to edit the roster or add Player 2. **Room settings** holds the mode, format, map, rules, and presets. **Portrait maze** makes rectangular maps taller than they are wide. The square Compact map keeps its dimensions.

Selecting **Teams** puts the top half of the active roster on Team 1 and the bottom half on Team 2. Team 1 gets the extra pilot when the count is odd. The player list keeps teammates together as assignments change.

**Share room online** opens the room to friends. Share the invite link or room code. Guests select **I'm Ready**, then the host starts the match. When another combatant joins, guests who already marked themselves ready keep their status. **Find online battle** opens public matchmaking. Fixed-maze rooms offer live spectator links. Infinity spectators wait in the lobby.

Fixed-maze rooms have eight combat seats. Survival has four squad seats, with enemy waves generated separately.

## Game modes

| Mode | Goal |
| --- | --- |
| Elimination | Be the last tank or team standing. |
| Capture the Flag | Return the enemy flag while your flag is at base. |
| King of the Hill | Hold the hill to earn points. |
| Survival | Clear waves with your squad. |
| Infinity | Explore an endless maze and score by destroying tanks. |

Bank shots around corners and collect glowing pickups. Your own shots and grenade blasts leave your tank unharmed. [Power-up guide](POWERUPS.md)

## Local development

Run `./dev.sh` or `go run ./src` from the repository root. The server uses port 8080 by default. Open [`src/web/index.html`](../src/web/index.html) directly in a browser for offline play.

After editing `version` in `src/main.go`, run `./scripts/vergen.sh` to move the browser assets and synchronize release references, then rebuild. Asset generators use `./scripts/icons.sh` and `./scripts/showcase.sh`.

The server allows up to 32,768 rooms by default. Use `MAX_ROOMS` or `-max-rooms` to set a lower limit.

The authoritative simulation and transport live in `src/`. The browser entry point is `src/web/index.html`, with assets under `src/web/assets/v<version>/`. The Go binary embeds the entry point and assets and serves the same versioned asset URLs.

[Test commands](TESTING.md) · [WebSocket protocol](PROTOCOL.md) · [Release notes](releases/) · [Changelog](../CHANGELOG.md)
