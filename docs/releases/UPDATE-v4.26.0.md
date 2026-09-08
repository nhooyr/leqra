# leqra v4.26.0 — Godlike bots, Safari audio and controls

## Godlike

Choose **Godlike bot** when adding a bot, or change an existing bot's difficulty to **Godlike**. It is available in local and online rooms, saved presets and every game mode.

Godlike plans ahead for grenade bodies, remote blasts and expiring fuses; predicts homing missile turns and ricochets; avoids exposed laser firing lines; evaluates firing safety; and seeks useful, reachable power-ups. Capture the Flag adds recovery, interception, carrier and escort decisions; King of the Hill prioritizes scoring position. Planning considers shields, speed, ghost movement, scope and every weapon type.

Godlike uses Fierce's movement and turning limits, with quicker decisions and more accurate aim. It follows ordinary weapon, ammunition, collision and damage rules. It cannot guarantee survival against every shot or win every match. Prediction and candidate counts are bounded to control CPU cost; this is a stronger heuristic bot, not an exhaustive perfect-play solver.

Navigation also tolerates human teammates without bot navigation state. Shared forecasts, a shortlist for expensive homing predictions, reusable planning buffers and cached wall queries keep the new difficulty practical. See the measured costs in the test notes.

## Safari audio

Removed an app-side defect matching the reported Controls/scrolling symptom: global touch events repeatedly attempted to unlock an eight-element native audio pool by playing a non-silent 25 Hz WAV at an assumed near-zero element volume. On iOS, that volume assumption is unsafe. No native unlock tones are played now, and ordinary menu scrolling no longer triggers audio initialization.

The game prefers its shared Web Audio graph; real fallback effects have their volume encoded in the generated samples. Volume changes ramp smoothly, finished effects disconnect their audio nodes, and delayed/muted/stale effects cannot accumulate into an unexpected burst. Audio initialization can retry after an interruption.

This removes a concrete application cause of unintended sound, but the exact crackle has not been reproduced on a physical iPhone in this environment. A Safari bug cannot be ruled in or out from the report alone. Apple documents the media-volume restriction in its [archived iOS audio guide](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/Using_HTML5_Audio_Video/Device-SpecificConsiderations/Device-SpecificConsiderations.html). WebKit has historical [scrolling-related audio crackle reports](https://bugs.webkit.org/show_bug.cgi?id=208233) and an [AudioContext interruption/resume report](https://bugs.webkit.org/show_bug.cgi?id=263627); these concern specific versions and pipelines and do not prove the cause in leqra.

An iPhone retest should open Controls and scroll repeatedly with sound enabled, repeat at zero volume/muted, then return to gameplay and background/foreground the app. Verify both Safari and an installed Home Screen copy, and note the iOS version if any noise remains.

## Controls and UI

- Both players now have editable **Fire** and **Fire (alternate)** bindings. Defaults are Q / C for Player 1 and Space / Enter for Player 2. Either key can fire or remotely detonate a deployed grenade.
- Whenever Player 2 is not active, all of their current configured movement and fire keys also control Player 1. Remapping either player does not disable this fallback. A spectating Player 2 counts as inactive.
- All twelve bindings must be unique. Existing saved remaps are preserved; missing alternate fire bindings receive C / Enter when available, otherwise an unused key. The field manual and summaries reflect the actual bindings, with long key names wrapping within the sidebar.
- Leaving/ending a match, joining another room, taking a room offline, returning to a matchmaking party, and replacing/deleting presets use the game's confirmation dialog. Cancel/Escape and focus restoration work consistently. Stale confirmations cannot act on a different room, match, host or preset.
- The battle format label is **Teams**. The field manual label is **Fire**.

## Upgrade

Replace the Go sources and complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. The server, browser assets and service-worker cache use **4.26.0** and `/assets/v4.26.0/`. This release retains the earlier team balancing, CTF team restrictions, match-only pause button, offline play and result/roster fixes.

See `TEST-NOTES-v4.26.0.md` for verification and `IMPROVEMENTS-v4.26.0.md` for gameplay proposals.
