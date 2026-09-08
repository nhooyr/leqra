# leqra v4.10 — ten-second powers, calmer Ghost feedback, and grenade ownership

## Ghost in-wall HUD no longer flashes gray

While Ghost is active, entering an internal wall still blocks ordinary firing and the
loadout text still reads **IN WALL · MOVE TO FIRE**. The colored cooldown/ammunition
bar no longer empties merely because the tank crossed into a wall. It continues to
show the real underlying cooldown or ammunition readiness, so moving rapidly in and
out of walls does not create a distracting gray/color flash.

Cannon remains able to fire while embedded in a wall, and an already-armed grenade
can still be remotely detonated there.

## Every timed power-up effect uses ten seconds

All timed effects now share a ten-second live-play duration:

- Machine gun
- Shotgun
- Shield stack timer
- Homing missile equip timer
- Grenade equip timer
- Super Speed stack timer
- Laser equip timer
- Cannon equip timer
- Scope
- Ghost

Charge-limited weapons can still end earlier when their last charge/volley is used.
Recollecting stackable/refreshable buffs keeps their existing stacking behavior and
refreshes the shared timer to ten seconds rather than adding another ten seconds.

## Uncollected pickups remain for 30 seconds

Fresh maze pickups now have a **30-second uncollected lifetime**, up from 19 seconds.
The final-three-second pulse/blink remains the expiry warning. Collection, map-scaled
pickup caps, safe placement, and host-selected spawn frequency are unchanged.

## Shotgun icon

The shared Shotgun icon is now a horizontal pump-shotgun silhouette with a stock,
receiver, fore-end and barrel. The exact same drawing function is still used in the
maze pickup, legend, and Rules power-up selector.

## Grenade avoidance follows ownership and friendly-fire rules

Bots continue to avoid the **grenade body and its predicted short path**, not the
220-unit blast radius. The ownership behavior is now:

- a bot always avoids **its own grenade**;
- a bot avoids **enemy grenades**;
- a bot ignores a teammate's grenade while friendly fire is **off**;
- a bot avoids a teammate's grenade while friendly fire is **on**.

This applies to local/browser bots and Go-server bots. The grenade itself remains a
normal impact-detonation object; this change only changes bot steering decisions.

## Audit and optimization fixes

The pass also fixed a small online presentation bug where a pickup could remain drawn
for one interpolation window after its authoritative lifetime had expired. The client
now drops that cosmetic pickup as soon as its extrapolated life reaches zero.

Grenade-body avoidance also received two hot-path cleanups: the client no longer
allocates a temporary `slice(1)` array to locate the nearest threat, and the Go bot AI
no longer preallocates a 16-entry threat buffer every tick when there is no relevant
grenade. A redundant nested risk-condition was removed as well.

## Upgrade

Replace the Go sources and complete `web/` directory, restart the server, and refresh
all clients:

```sh
cd leqra-online
go run .
```

Both `/healthz` and `leqra.version` should report **4.10.0**. Rebuild compiled or
Docker deployments because the Go executable embeds the browser files.
