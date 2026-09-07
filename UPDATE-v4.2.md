# leqra v4.2 — stable cooldowns and smoother online firing

## What was causing the flicker

Two separate problems were reproduced against the original v4.1 browser code.
The general HUD refreshed FIRE/BOOM while the combat-feedback routine refreshed
the countdown text. Those writers alternated, so the Fire button could flicker
even during ordinary play. Separately, Go freezes a tank's weapon cooldown at the
end of a round, but the browser kept subtracting elapsed time between snapshots.
Every incoming snapshot restored the same frozen value, creating a sawtooth bar.

The combat-feedback routine now exclusively controls the Fire button, accessible
label and cooldown fill. It uses stable **ROUND COMPLETE** and **MATCH COMPLETE**
states after a win, with **DONE** on the mobile button. Countdown and pause also
have explicit states. Nonplaying snapshots no longer animate weapon readiness
as if live firing continued. The same behavior applies to both local pilots.

## Online firing responds locally

A locally eligible Fire action immediately produces a cosmetic muzzle flash,
shot sound, recoil and projectile/laser preview. Holding an automatic weapon
continues to use its existing cooldown. This applies independently to both
keyboard players and to the primary mobile Fire control.

Go assigns a volley identity to each accepted shot and includes it in tank,
projectile and effect snapshots. The client matches the preview to that identity
instead of drawing a second shot or replaying its firing sound on confirmation.
Scatter's individual pellets also have identities. Previewed laser confirmation
corrects the remaining beam instead of restarting its flash. Lasers still bypass
the normal projectile-slot limit when old shells are in flight.

**This is visual prediction, not client-authoritative combat.** The browser does
not award damage, kills, score, pickups or extra ammunition. The actual ammo and
owned-grenade checks use the newest authoritative state, not cosmetic projectiles.
Go still validates weapon charges, cooldowns, walls, teams and all hits. Remote
grenade detonation remains server-confirmed; its hold/press rules are unchanged.

A preview may be corrected or removed if the server rejects it, the tank dies,
or a connection stalls. Unconfirmed projectile previews travel for at most
0.35 seconds and then disappear rather than drifting indefinitely. The pending
bookkeeping has a 250–900 ms timeout and bounded per-player entries. A reconnect,
new maze/life or removed controller cannot keep firing an old preview.

## Projectiles and other tanks follow a continuous presentation timeline

Previously, a new remote projectile could first appear at the newest network
position and then jump backward when older buffered samples became available.
Remote projectiles now enter on the same buffered timeline as their shooters;
remote shot/laser effects are scheduled against their simulation tick as well.

Your own confirmed projectile remains on its local birth-time clock rather than
restarting its animation clock at each network packet. This removes the tested
preview-to-confirmation rewind and packet-arrival stepping. Short extrapolation
uses the existing wall, rim, drag, lifetime and missile-range rules. It is bounded
and does not choose homing targets or simulate damage on the client.

Remote tank extrapolation previously handled position but stopped turning in a
brief snapshot gap. It now also continues a bounded estimate of angular motion
for the existing maximum 75 ms gap. Respawns, deaths and changed life identities
are not treated as continuous motion. Severe gaps can still freeze or correct;
this does not conceal an indefinitely disconnected player.

Screen shake is localized to relevant nearby impacts/local damage rather than
shaking the whole view for distant kills. Spectators no longer receive unrelated
whole-arena shakes. Existing reduced-motion preferences remain respected.

## Other bug checks and optimization

The audit added regressions for accepted/rejected volley IDs, pellet ownership,
laser slots, grenade press/hold behavior, duplicate effects, stale previews,
respawns, both local players, frozen result scores and reconnect cleanup.
Ghost + Speed, Cannon boundaries, shared icons, room controls, spectators and
matchmaking also passed their existing feature checks. This is a targeted audit,
not a claim that every possible game bug has been eliminated.

Online cosmetic work now runs once per animation frame instead of repeating
particle/effect/HUD-adjacent work in the 120 Hz simulation loop. The online
movement predictor still advances its own fixed 60 Hz steps; Go remains at
60 simulation ticks and 30 snapshots per second. Offline physics remains 120 Hz.
Particle drag is calculated once per update rather than per coordinate/particle.
Unchanged Fire styles/attributes are not rewritten, and duplicate forced input
packets for an unaffected local player are skipped while logical input edges and
normal heartbeat delivery are retained. Menu checks avoid a temporary node array.

The existing spatial wall index, cached map/tank drawing and room-wide snapshot
encoding remain in use. There is **no WebGL port, device FPS guarantee, new weapon
balance, or change to movement speed, damage, power-up timing or win conditions**.
The client networking module changed for shot presentation and angular gap handling;
the previous movement input-replay rules remain in place.

## Install

Stop the old Go server. Back up custom deployment settings, and replace **all Go
sources and the entire web/ directory** with this package. From the extracted folder:

```sh
cd leqra-online
go run .
```

Refresh every player's and spectator's browser. `/healthz` and `leqra.version`
should report **4.2.0**. Update both ends: older servers do not send the volley/life
metadata needed to reconcile previews correctly.

A compiled executable embeds web assets and must be rebuilt:

```sh
go build -trimpath -o leqra .
./leqra
```

Use `leqra.exe` on Windows. Existing Docker Compose deployments can use
`docker compose up --build -d`, preserving their custom settings. Restarting
clears in-memory rooms, queues, matches, scores and chat; browser-saved presets,
controls and display preferences remain. No new game runtime dependency, npm
step, account system or database is introduced. This does not deploy a public server.

## Verification and limits

See **TEST-NOTES-v4.2.md** and **TESTING.md** for actual runs and commands. The
original v4.1 cooldown-writer conflict, frozen-round bar sawtooth and remote-shot
rewind were reproduced before checking their fixes. Browser tests cover four
viewport sizes and a real Go server with synthetic delay for both local players.

Testing used Chromium desktop/mobile emulation, injected game assets and synthetic
Location/History/storage adapters, with real local Go WebSockets. Physical phones,
Safari/Firefox, physical speakers, actual public internet hosting, real packet loss
and production capacity were not tested. Local visual response cannot eliminate
the real time needed for the server to receive a shot and confirm a hit.
