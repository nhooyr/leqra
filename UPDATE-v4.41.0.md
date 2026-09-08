# leqra v4.41.0

## Power-up badges

Bot and remote-tank power-up icons pulse during their final three seconds, using the same animation clock and opacity curve as expiring uncollected pickups. The icon and its corner count fade together.

Corner numbers show remaining weapon ammunition: machine-gun rounds (up to 180), Shotgun volleys, or Laser/Homing/Grenade/Cannon charges. Shield and Speed show their current stacks. Scope and Ghost have no ammunition or stacks to display. Local pilots retain their full ammo/status HUD.

The existing close clockwise positions remain fixed relative to each tank at maze edges. Countdown, pause and Survival-break timers stay frozen. Blinking and count changes do not rearrange the icons or tank label.

## Sound balance and fixes

Ricochets and quieter remote weapon cues are more audible; death and other loud effects are reduced. Local and online shield impacts now use the same cue. Weapon pitches, wave shapes and timings are retained. The slider still defaults to 50%, preserves saved values, and retains the existing master gain and peak protection.

An explosion and its simultaneous victims now share one sound cue rather than multiplying death audio for every tank. Online ricochets previously had no sound path; they now follow visible projectile bounces with a bounded history and a short shared throttle. Joining or reconnecting does not replay old bounces.

A native-audio quality check found that separately safe sound layers could exceed full scale when added together. Death, Laser and Cannon now share a gain budget across their layers, preserving relative levels and increasing through 100% without clipping within those individual generated cues. Pickup and chat cues also passed the summed-layer check. Actual browser/device mixing and listening quality still require a physical-device retest.

## Other fixes and optimization

Online movement remains interpolated, while power-up types, ammo and stacks now come from the newest server state. All power-up timers age consistently between snapshots, so stale buffered loadouts cannot show old equipment or delay the expiry warning.

Survival breaks clear pending movement prediction for both local pilots and freeze tank positions and buffs. This prevents previous-wave input from moving a tank or expiring Ghost during the break. Prediction resumes during active play.

Server wall queries now enumerate a reusable ordered bit mask instead of gathering, deduplicating and sorting wall IDs. Exact candidate and collision comparisons pass. Complete aiming queries took approximately 18% less time in the isolated benchmark, with 6% and 11% reductions for movement and long-ray cases. These are query measurements, not game FPS. Badge sprites stay cached independently of changing ammo numbers.

## Lobby action

The lobby action is now **PLAY**, immediately above **ROOM NAME / CODE**, so it appears earlier on mobile. It retains its centered primary style and existing start/readiness behavior. Results retain **PLAY AGAIN**.

## Install

Replace the Go sources and complete `web/` folder, then rebuild and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh clients afterward. Server, browser, versioned assets and offline cache use **4.41.0**. Online client and server versions must match.

See `TEST-NOTES-v4.41.0.md` for validation and `PERFORMANCE-v4.41.0.md` for the benchmark method and limits.
