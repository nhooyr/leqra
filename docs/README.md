# leqra player guide

## Controls

- **Primary tank (P1)** uses W/S to drive forward and back, A/D to steer, and Q/C to fire.
- **Second local tank (P2)** uses the arrow keys and Space/Enter. These keys also control the primary tank when the second tank is inactive.
- **Touch** uses the joystick to drive and steer. Tap Fire to shoot, or hold it to fire continuously. Drag Fire to aim the turret while firing, even while driving in another direction; the crosshair follows your aim. Release or cancel the touch to stop firing. Push the stick further for a faster wide turn. Touch near your tank to aim without moving or firing. Press Fire again to detonate an active grenade.
- **P or Esc** opens the in-game menu. **M** toggles sound and **F** toggles fullscreen.
- **Mouse** aims the primary tank; left-click or hold to fire. A/D switch back to keyboard aiming until the pointer moves again. Mouse Aim and Mouse Fire have separate checkboxes in Controls.

On a phone or tablet, manually enable **Local P2** to play together: touch stays
with P1, and a connected keyboard/mouse controls P2. Both keyboard layouts above
control P2 in this setup. Each pilot has a separate callsign, color, score, and
loadout. Infinity uses two camera views, side by side in landscape or stacked in
portrait; fixed mazes share one view.

Open **Controls**, below **Players and bots**, to remap keys, toggle mouse controls, adjust audio, or replay the quick tour. Callsign fields are above the settings sections and are also available in pause menus, including Infinity.

Open **Controls → Showcase** for a frozen battle ready for screenshots. It uses
the full gameplay header and status bar on desktop and mobile. Take screenshots
directly here; no generator or Chrome overrides are needed. Press **Escape** to return with
a keyboard. On mobile, switch away from the app and come back. There are no
extra exit buttons over the screenshot.
Desktop uses a denser battle with twenty tanks, twenty-six loose pickups and
projectile volleys across the arena. Mobile keeps its separate compositions.
On phones and tablets, Showcase includes the gameplay header, touch controls,
and loadout bar. Portrait uses a compact scene with ten tanks and four loose
pickups; all ten power-ups are demonstrated on equipped tanks. Both compositions
show a ricocheting laser destroying one tank while its callsign stays visible,
with the beam clear of the other tanks. Cannon trails remain visible in the
frozen battle.

## Rooms

The **Infinity** switch is on by default. Press **Play** to roam a public endless maze with up to 32 player tanks. Roaming bots have a shared budget of 16 per connected player, up to 512. All ten power-ups can spawn. One unprotected hit destroys a tank. You gain a point for each tank you destroy and lose a point each time you die. Tanks respawn after one second, and the leaderboard shows the ten highest current scores.

Select **Infinity** under **Room settings → Game mode** to use your own roster. Up to eight tanks can occupy roster seats, including local Player 2 and configured bots. In **Rules**, you can enable additional roaming bots and choose their difficulty. Set a positive score target to play to a win, or leave it at zero for endless exploration. Use **Share Infinity room** to invite friends to the arena. Guests ready up and the host presses **Play**.

To enter public Infinity with an online room, the host enables **Infinity**, guests ready up, and the host presses **Play**. Everyone competes individually, with consistent tank colors. The sidebar keeps room members visible below the top ten when needed. The whole party must fit the public arena. Successful entry clears configured room bots; public roaming bots spawn independently.

While **Public Infinity** is enabled, Room settings keeps only the room name and
sharing actions. Turn it off to choose a room mode, battle format, map, rules, or
presets. Your saved room configuration is retained.

New rooms start with Player 1 only. Turn off **Infinity** to play the selected room mode; if there are no bots, Player 2, or other online players in combat seats, three Medium bots join automatically. Open **Players and bots** to edit the roster or add Player 2. **Room settings** holds the mode, format, map, rules, and presets. **Portrait maze** makes rectangular maps taller than they are wide. The square Compact map keeps its dimensions.

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

After editing `version` in `src/main.go`, run `./scripts/gen-version.sh` to move the browser assets and synchronize release references, then rebuild. Generate icon assets with `./scripts/gen-icons.sh`.

Capture showcase screenshots directly from **Controls → Showcase**.
After saving `docs/showcase.png`, run `./scripts/gen-featured-android.sh` to
generate `docs/showcase-featured-android.png`. It detects the arena center, scales
the full image width to 1024 pixels, and crops vertically to 500 pixels around
the player tank. The maze keeps its full width and proportions, without padding.
For an image with the arena borders removed, supply `-center X,Y` in source
pixels; X must be the image's horizontal midpoint. The script uses Go's standard
PNG support and needs no image tools.

All shell scripts in `scripts/` can be called by absolute path or through `PATH` from any directory. Relative output arguments use your current directory.

The server allows up to 32,768 rooms by default. Use `MAX_ROOMS` or `-max-rooms` to set a lower limit.

The authoritative simulation and transport live in `src/`. The browser entry point is `src/web/index.html`, with assets under `src/web/assets/v<version>/`. The Go binary embeds the entry point and assets and serves the same versioned asset URLs.

[Test commands](TESTING.md), [WebSocket protocol](PROTOCOL.md), [Release notes](releases/), [Changelog](../CHANGELOG.md)
