# leqra v4.28.0 — mode slider and bot navigation

## Home-screen mode selection

Choose Elimination, Capture the Flag, King of the Hill or Co-op Survival directly on the home screen. Each mode has its own icon. Tap an icon or drag the discrete slider; keyboard users can focus the slider and use its arrow keys. The selected mode has a visible label and a short explanation.

The old **RULES & MODE** action is now **RULES**. Mode selection has moved out of the dialog; Rules contains the format, map, score/wave target, timer, power-ups and other settings for the selected mode.

Changing mode retains the map and power-up settings and applies the same mode-specific score/time defaults as the previous dropdown. Capture the Flag uses Teams 1 and 2; Survival uses one squad on Team 1. A Survival selection with more than four active tanks is rejected without removing anyone. Online guests and active matches cannot change the mode. Online selection waits for the server's accepted room state, with failures explained beside the control. Presets and reconnects also update the selection.

## Sidebar bot levels

**THE LINEUP** shows each bot's AI level, using the same Chill, Normal, Fierce and Godlike names as the room controls. Mixed human/bot teams identify each bot individually. Free-for-all and the legacy solo bot squad show the levels too. Room difficulty edits update these labels without requiring a new match.

## Bots finish their approach

Two navigation problems could leave bots short of their destination. The local controller applied its enemy stand-off distance to interaction targets, even though pickups and objectives require much closer contact. Both runtimes could also retain waypoints they had already bypassed while taking a shortcut, causing unnecessary turns back toward those points.

Bots now use a precise final approach for pickups, flags and bases, consume skipped waypoints, and move directly to visible interaction points when their full hull fits. They prioritize finishing an objective approach instead of repeatedly interrupting it to change firing position. Hill holding requires a visible scoring position; being close to the hill on the other side of a wall no longer counts as having arrived. Existing projectile avoidance, movement limits and damage rules still apply.

The changes apply locally and on the Go server. They retain v4.27's survival mode, Godlike bosses, 15-second power-ups on Huge and larger maps, five-second machine-gun firing budget and minimum 30-second uncollected pickup lifetime on Large and smaller maps.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser files are embedded in the executable, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh each player's browser; the client/server handshake requires the same application version.

The server and browser report **4.28.0**. Browser assets, including the manifest, use **`/assets/v4.28.0/`**, and the service-worker shell uses the matching cache version. Offline local play and existing installation support are retained.

See [TEST-NOTES-v4.28.0.md](TEST-NOTES-v4.28.0.md) for executed checks and remaining verification limits.
