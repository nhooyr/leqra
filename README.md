# leqra

[leqra.com](https://leqra.com)

An online multiplayer tank arena battle game.

![screenshot of the game](docs/screenshot.png)

- 5 fun free-for-all and team based game modes:
    1. Infinity
    2. Elimination
    3. Capture the flag
    4. King of the hill
    5. Survival
- 10 collectable power-ups:
    1. Cannon
    2. Ghost
    3. Laser with a ricochet aim guide
    4. Homing missile
    5. Grenade
    6. Super speed
    7. Machine gun
    8. Shotgun
    9. Shield
   10. Starman
- Flexible lobby rooms supporting:
    1. Public Infinity
    2. Local players
    3. Bots
    4. Online players
    5. Teams
    6. Spectators
    7. Online matchmaking
- 4 bot levels:
    1. Chill
    2. Normal
    3. Fierce
    4. Godlike
- 6 map sizes. 11 including the portrait toggle.
- Public Infinity supports up to 32 player tanks and 24 roaming bots, for up to 56 tanks in one arena.
- Private Rooms support 8 tanks at a time in any game mode.
- Mouse, keyboard and touch controls.
- Quick tour on first startup.
- A second local player.
- Mobile & PWA support.
- Managed deployments to minimize downtime.

## Getting Started

You can open [./src/web/index.html](./src/web/index.html) to play offline.

To run a local server:

```sh
./dev.sh
```

You can deploy the binary anywhere as all assets are embedded.

```sh
go build -trimpath -o ./bin/leqra ./src
```

See [./deploy/ensure.sh](./deploy/ensure.sh) for how I deploy it to [leqra.com](https://leqra.com).
