# leqra v4.29.0 — clearer controls, mobile input and CTF teamwork

## Requested changes

- **Machine gun:** each pickup provides 180 successful shots, equivalent to **three seconds of active firing** at 60 rounds/second. Idle, blocked and rejected shots do not spend the budget. The existing 10-second equip timer, or 15 seconds on Huge and larger maps, still applies. Each local pilot sees **FIRE 3.0s** counting down beside ammo, including pending online shots. The readout occupies the existing fixed-height status row.
- **Laser icon:** a compact emitter and narrow illuminated beam replace the radial impact burst. The shared drawing updates maze pickups, the legend and menu icons.
- **CTF:** supporting bots use nearby cover instead of crowding the home-base center when an ally carries the enemy flag. The carrier has space to approach and capture. This applies locally and on the server, for all four difficulties and human or bot carriers. Flag recovery and combat avoidance remain active.
- **Fullscreen:** **F** works from Rules, Presets, Controls and Find Online Battle, as well as other menus. Text entry, native select typeahead, key remapping and system shortcuts keep their keys. Holding F does not repeatedly toggle fullscreen.
- **Game Mode:** the extra range slider is removed. The four icon buttons remain, with arrow/Home/End navigation and one keyboard tab stop. Selected color is painted directly on the button so it remains visible on mobile without relying on hover.
- **Rules summary:** complete items wrap together. Labels such as **FRIENDLY FIRE OFF** cannot split across lines.
- **Mobile gestures:** pinch zoom is suppressed throughout active matches, including countdowns, pauses, intermissions and open dialogs. Joystick + Fire pointers remain independent, and menus retain single-finger scrolling. Home, lobby and completed matches release the match-specific zoom lock.

## Additional fixes and optimization

Open chat now keeps only the retained 60 messages per channel in the document instead of accumulating rows indefinitely. Evicting old rows preserves the reader's scroll position. Reconnect recovery preserves unconfirmed outgoing text without automatically resending it or changing its recipient.

CTF cover planning uses a small bounded candidate set and a short cache. The rules summary skips unchanged document updates. Gesture-blocking listeners are installed only while a match is active and are removed afterward.

Subjective gameplay/UI ideas have not been implemented and remain proposals for approval.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded, so existing executables or Docker images must be rebuilt. Restarting clears in-memory rooms and scores. Refresh each player's browser; server and client must both report **4.29.0**.

All browser assets use **`/assets/v4.29.0/`**, with the matching PWA registration and service-worker cache. Wire protocol remains **1**. Offline local play and installation support are retained.

See [TEST-NOTES-v4.29.0.md](TEST-NOTES-v4.29.0.md) for executed checks and verification limits.
