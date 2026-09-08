# leqra v4.30.0 — Survival previews and clearer status

## Survival

The mode is now named **Survival** throughout the home selector, Rules, Field Manual, built-in preset, result screens and validation messages. The internal `survival` mode identifier is unchanged, so existing room settings and saved presets still work. User-named saved presets retain their names.

Before a boss wave, the existing four-second intermission shows **NEXT: WAVE 5 · GODLIKE BOSS** (or the upcoming boss wave number) and the boss's starting equipment. The preview reflects enabled Shield and Speed boosts and the selected Homing/Cannon/Laser weapon. Disabled pickups do not appear as boss equipment. The countdown continues normally, and the preview disappears when the wave begins.

## THE LINEUP

Each tank in a team now occupies its own line, with its existing AI level where applicable. Team names and scores remain together above/beside their members.

Survival adds the current wave's enemy bots to THE LINEUP, including Chill, Normal, Fierce or Godlike strength labels and an explicit boss marker. The online view uses authoritative enemy tanks. Wave changes replace those entries, and returning to the room removes them. Enemy rows show combat status without adding false score pips.

## Machine-gun ammo display

The previous tiny firing counter has been replaced with a clearer **FIRE LEFT** readout, remaining time against the **3-second total**, and a live depletion bar. Each local player has an independent display, including unacknowledged online shots. Releasing Fire preserves the firing budget; idle and blocked attempts do not spend it. The separate 10/15-second equip timer is marked **EXPIRES**.

The ammo/status area retains its fixed height. The machine gun still grants 180 successful rapid shots at a maximum of 60 shots per second.

## Rules-summary wrapping

Summary items remain whole. Separators sit between items and disappear at the start of wrapped lines, including before **FRIENDLY FIRE OFF**. This uses CSS layout without per-frame line measurements.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. Browser assets are embedded in the executable, so rebuild existing executables or Docker images. Restarting clears in-memory rooms and scores. Refresh players' browsers so client and server both report **4.30.0**.

Browser assets, PWA registration and service-worker cache use **`/assets/v4.30.0/`**. Wire protocol remains **1**. Offline play and installation support are retained.

See [TEST-NOTES-v4.30.0.md](TEST-NOTES-v4.30.0.md) for executed checks and verification limits.
