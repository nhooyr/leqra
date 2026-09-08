# leqra v4.9 — grenade-aware bots, quarter-range Machine gun, and build info

## Bots avoid the grenade body, not its whole blast radius

Bots now treat every live grenade as a small moving physical hazard. Their steering
predicts the grenade's short-term path (including drag and wall bounces) and tries to
brake, reverse, or steer around the grenade body before tank contact can trigger the
explosion.

This avoidance deliberately uses only the grenade radius plus a small clearance
margin. Bots do **not** treat the 220-world-unit explosion radius as a forbidden zone.
A grenade that is nearby but clearly off the bot's driving path therefore does not
make the bot abandon its route. Friendly grenades are avoided too, because touching
one can detonate it even when teammate damage is disabled.

Basic grenade-body avoidance also applies to Chill bots. Normal/Fierce retain their
existing projectile dodging in addition to this new grenade obstacle pass. The final
movement command is checked, so stuck-recovery steering cannot override grenade
avoidance and drive the bot into the grenade.

Local-browser bots and Go-hosted online bots use matching behavior.

## Machine gun range is one quarter of the maze perimeter

Every Machine gun round now has a total path budget of:

**(maze width + maze height) / 2**

Because the maze perimeter is `2 × (width + height)`, this is one quarter of the
perimeter. The hidden muzzle section and every ricochet count toward the same budget;
bouncing never restores range. Shooter immunity and the 60 Hz continuous-fire rule
are unchanged.

The shorter maximum flight means the active Machine gun cap is reduced from 192 to
**96 rounds per tank**. On the largest 16×14 map that still exceeds the number needed
to sustain a full 60-round/s stream for the complete quarter-perimeter flight. The
compact browser decoder is correspondingly bounded at 768 records for eight tanks,
reducing worst-case projectile state work without dropping legitimate rounds.

Bot firing prediction uses the same quarter-perimeter range as authoritative shots.

## Version in Controls

The Controls menu now shows **leqra v4.9.0** at the bottom. The browser public
state, `/healthz`, and `/api/config` report the same version.

## Field Manual wording

The sidebar now says:

**Use Controls menu to change keys.**

instead of “Use Controls to change keys.”

## Upgrade

Stop the existing server, preserve custom deployment settings, and replace all Go
sources and the complete `web/` directory.

```sh
cd leqra-online
go run .
```

Refresh every player and spectator after restarting. Compiled and Docker deployments
must be rebuilt because browser assets are embedded in the Go executable.

## Verification

The final source passed `go test -race ./...` with 844 test/subtest passes and two
existing opt-in skips, all 56 Node JavaScript tests, eight focused Chromium assertions,
`go vet ./...`, JavaScript syntax checks, and a compiled server build. A local health
check confirmed both `/healthz` and `/api/config` report version 4.9.0.

Browser testing uses Chromium emulation and local files/servers; it does not substitute
for physical-phone, Safari/Firefox, real internet packet-loss, or production-capacity
testing.
