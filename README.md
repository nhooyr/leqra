# leqra

[leqra.com](https://leqra.com)

An online multiplayer tank arena battle game.

![screenshot of the game](docs/screenshot.png)

- 4 fun free-for-all and team based game modes:
    1. Elimination
    2. Capture the flag
    3. King of the hill
    4. Survival
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
    1. Local players
    2. Bots
    3. Online players
    4. Teams
    5. Spectators
    6. Online matchmaking
- 4 bot levels:
    1. Chill
    2. Normal
    3. Fierce
    4. Godlike
- 6 map sizes.
- 8 tanks at a time.
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
