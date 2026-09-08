# leqra v4.27 — the ten power-ups

> Current rules: friendly fire is optional; **Machine gun, Shotgun and Laser never damage their own shooter**. Other returning shells/missiles and grenade blasts can. See UPDATE-v4.27.0.md for current timing, survival and bot changes.


Drive over a glowing pickup to collect it. The same pickups are available in
local rooms and shared online rooms, including mixed human/bot teams. Every
weapon uses the existing Fire control: **Q / C**, mobile FIRE, or Player 2's **Space / Enter**. Both players can remap both fire keys; all configured P2 keys also control P1 while P2 is inactive.

Equipped weapons and buffs last **10 seconds on Compact, Standard and Large**, or **15 seconds on Huge, Giant and Ultra Wide**. The table below uses “10/15 seconds” for this map-dependent duration. Projectile flight and grenade fuses remain separate.

| Pickup | Effect | Duration / charges |
| --- | --- | --- |
| Machine gun | ⅓-diameter, 3×-speed ricochets; shooter-safe; one quarter-perimeter total path. No weapon cooldown; up to 60 rounds/s. | 10/15 seconds to use; 180 rounds (3 seconds of firing); 96 active slots |
| Shotgun | Three spreading ricochets at 3× normal speed; cannot damage their shooter. | 5 volleys or 10/15 seconds; 0.54s cooldown |
| Shield | Adds one protective charge, up to five rings/charges; 3× individual spawn weight. | Shared 10/15-second timer, refreshed on collection |
| Homing missile | Aggressive bounded tracking, wall ricochets, and a half-perimeter total travel limit. | 3 missiles or 10/15 seconds |
| Grenade | Bounces off walls; explodes on tank impact, another Fire press, or the **10-second fuse**. **220-unit blast radius**; walls block blasts. | 3 throws or 10/15 seconds |
| Super speed | Adds +65% movement and +25% turning per stack, up to five stacks; 3× individual spawn weight. | Shared 10/15-second timer, refreshed on collection |
| Laser | Instant wall-bouncing beam, limited by maze perimeter; stops at the first vulnerable tank. | 3 shots or 10/15 seconds |
| Cannon | Pierces internal walls, ricochets at the outer rim; 4× normal diameter and speed. Stops on a damaging tank hit. | 3 shots or 10/15 seconds; 0.85s cooldown |
| Scope | Extends the dotted aiming guide to half the maze perimeter, including reflected segments. Does not change actual projectile range. | 10/15 seconds; independent buff |
| Ghost | Tank passes through internal walls while the arena rim stays solid. Stacks with speed, shield, Scope and weapons. | 10/15 seconds; independent buff |

## Shields: five charges, five rings

Each Shield pickup adds **one charge, up to five**. The tank shows one concentric
ring per charge; the named ammo panel shows **SHD × N**. A damaging hit consumes
one charge, not the whole stack. The existing 0.35-second post-hit protection
prevents simultaneous pellets from stripping several charges in one impact.
Friendly-fire protection, spawn protection, and weapon-specific shooter immunity
still apply before a shield is consumed.

All charges share a **10/15-second timer**. Every collection refreshes
that timer, including collection at the five-charge cap. It does not add another full
duration per charge. Remaining charges expire together, and a new life/round
resets them. Shield remains independent of weapons, Scope, Ghost, and Super Speed.
Both local players have separate counts and rings. Stacked buff labels use fixed
HUD rows and compact text on phones, without resizing the maze.

Shield and Super Speed each have spawn weight **3**; every other enabled pickup
has weight **1**. With all ten types enabled the total weight is 14, so Shield and
Speed each have **3/14 ≈ 21.43%**, and each other type **1/14 ≈ 7.14%**. Disabled
types have no chance. Starting and timed pickups both use the same weights.
Map-scaled caps, starting stock, Super fast timing, and placement checks are unchanged.

## Super Speed: five stacks

Each Speed pickup adds one stack, up to five, and refreshes the shared 10/15-second
timer. One stack retains the previous +65% movement / +25% turn effect. Stacks add
linearly: five stacks are **4.25× base movement** and **2.25× base turning**. The
HUD shows `SPD×N`, and the tank draws additional speed streaks for each stack.
All stacks expire together and reset on a new life. Speed remains independent of
weapons, Shield, Scope, and Ghost.

## Shotgun replaces Triple shot

**SHOTGUN** fires three spreading pellets at **846 world units/second**, three
times the standard projectile speed of 282. Pellet diameter remains **7 world
units**, the same as a normal shell. They ricochet using ordinary wall geometry.

Shotgun pellets **never damage their own shooter or consume that shooter's shields**,
even after bouncing or after the owner changes weapons. Other enemies, friendly
fire when enabled, spawn protection, and shield absorption follow ordinary rules.
The existing **five volleys**, now paired with the common 10/15-second equip timer, 0.54-second cooldown,
and 3.9-second pellet lifetime remain. The visible name and shared legend/maze icon
are updated. No scatter pellet gains extra damage or wall penetration.

## Machine gun replaces Rapid fire

**MACHINE GUN** fires while Fire is held, with **zero weapon cooldown**.
Each round has **one-third normal diameter** (7/3 ≈ 2.33 world units) and
**three times normal speed** (846 world units/second). It uses a compact eight-unit
visual speed streak rather than allocating a history trail for every round.

Machine gun rounds **cannot damage their shooter or consume the shooter's shields**,
including after ricocheting or after the weapon is replaced. Every round has one
total travel budget of **(maze width + maze height) / 2 — one quarter of the maze perimeter**. The
hidden muzzle section counts toward that budget, and wall bounces do not reset it.
A higher defensive bounce ceiling prevents the old ordinary-shell 22-bounce guard
from cutting that requested range short on Giant maps.

Zero cooldown is not an infinite same-instant emission loop: **at most one round
per 60 Hz firing step, up to 60 rounds/second**. The same rate is used locally and
by Go, including when the local physics/render rate is higher. The weapon remains
available for **10/15 seconds**, with **180 successful rounds** per pickup: three seconds of full-rate firing. Idle or blocked attempts do not spend rounds; the regular equip timer still runs. It has **96 active-projectile slots per owner** while
equipped, enough to sustain a full-rate stream for the quarter-perimeter range on the
16×14 map while still bounding the cloud. Old projectiles can occupy slots; damage
authority remains on Go. The HUD shows **FIRE LEFT** with the remaining firing time.

Existing Fire bindings, remapping, both local players, and mobile Fire work as
before. An already-armed grenade still takes priority on the next new Fire press.
In-wall firing restrictions during Ghost remain, except for Cannon as before.

### Keeping the stream bounded and responsive

Immediate local previews still reconcile with accepted server volleys. Machine
gun uses a bounded preview history and compact numeric projectile samples in the
online protocol. Its trails, muzzle effects, and sound calls are deliberately
throttled; **the actual simulated rounds are not omitted**. Other weapons keep
their existing snapshot objects. The existing movement-input replay rules and
server 60 Hz simulation / 30 Hz snapshot rates are retained.

The compact protocol remains bounded at **768 Machine gun records**, matching the
worst-case eight-player 96-round active caps. The server preallocates common state
slices and maps canonical projectile colors in constant time. Eight simultaneous
streams still require materially more simulation and bandwidth than low-rate weapons;
this bound is not a production-capacity or FPS guarantee.


## Grenade

Grenades bounce, detonate on living-tank impact, and support the owner's
release-then-press **remote detonation**. The automatic fuse is **10 seconds** and
the explosion reaches **220 world units**. Their movement now matches that long fuse:
they retain roughly **88% of launch speed halfway through the fuse** and roughly
**76% with two seconds remaining**, then brake progressively harder during the final
seconds. Walls still block blast damage, shields absorb one hit, and the thrower can
be caught by their own explosion. The cosmetic shock ring matches the gameplay radius.

## Cannon

Cannon has a **14-unit collision radius (28-unit diameter)** and travels at
**1,128 world units/second**: four times normal diameter and speed. Its visible
projectile is enlarged accordingly. Internal walls do not deflect or slow it,
even at the muzzle; they are not destroyed. The outer arena rim **does** reflect
it, including at corners. Muzzle clearance accounts for the enlarged projectile.

A damage-eligible tank hit consumes the projectile, with shields absorbing one
hit. There is no splash damage or tank piercing. Its **5.3-second lifetime**
never refills on a bounce. A returned Cannon can hit its launcher after the normal
launch grace. Friendly-fire rules still apply.

Both dotted aiming guides pass through internal walls and reflect only at the
rim while Cannon is equipped. Bots and online projectile rendering follow the
same collision model. See **UPDATE-v4.1.md** for details.

## Ghost

The pale-blue Ghost pickup grants **10/15 seconds of wall-phasing movement**.
It is an independent buff; **every active Super Speed stack keeps its +65% movement** while
Ghost is active. Weapons, Shield and Scope also coexist. Recollection refreshes
only Ghost to the map duration, without stacking duration. The tank is translucent
with a dashed outline; each local pilot has a separate `GHO` timer.

The outer rim remains solid, and tank collisions and damage remain enabled.
Ordinary weapons do not gain wall piercing. When the tank centre is embedded in
a wall, ordinary Fire is blocked without consuming ammo; move clear to shoot.
Cannon still fires through walls. Remote detonation of an already-armed grenade
still works. Ghost is not invisibility to bots, invulnerability or a damage boost.

If Ghost expires inside a wall, choose the nearest safe cell-interior point,
without killing the tank or granting a new life/protection. Expiry in open space
does not reposition it. Life/round and sudden-death resets clear the timer.
Go, local simulation and network prediction use the same movement/expiry rules.

## Faster spawning

Pickup caps are `round(columns × rows / 9.8)`: **5 / 7 / 12 / 17 / 23 / 34** for
7×7 / 9×8 / 12×10 / 14×12 / 16×14 / 24×14. Initial stock is
**2 / 3 / 4 / 5 / 6 / 7**. Off or an empty enabled-pickup list prevents both initial
and subsequent pickups. The default Super fast setting attempts the first extra spawn
one second into live play, then every 1–2 seconds. Safe placement avoids tanks and
other pickups; a blocked/full arena skips that attempt. Uncollected pickup lifetime is
`floor(maximum pickups × 8/3)` seconds, with a 30-second minimum on Large and smaller. The six sizes expire after
**30 / 30 / 32 / 45 / 61 / 90 seconds** respectively.

## Scope

The blue reticle pickup automatically extends the collecting pilot's dotted
barrel-direction guide to **world width + height**, half the maze perimeter.
All reflections count toward the same total distance budget. The muzzle section
is hidden but counts toward that budget. Walls block/reflect the guide (except
when Cannon is equipped, which passes through internal walls but reflects at the rim), and
vulnerable tanks can stop it; friendly-fire settings determine eligible hits.
The actual visible length can therefore be shorter than the maximum.

Scope lasts **10/15 live-play seconds** and has no firing charges. It stacks with
weapons, speed and shields; collecting it again refreshes the timer to ten,
not twenty. It is cleared on the next life/round and sudden-death reset. Death
hides the guide. Local pause freezes the timer; an online menu does not pause it.

Both locally controlled pilots have their own guide and `SCP` countdown. Only
owned live tanks draw a personal guide: enemy/bot scopes are not additional
lines on your screen, and spectators do not acquire a scope by spectating.

This is an aiming aid, not aim assist, fog-of-war removal, zoom or extra damage.
It does not predict homing curves or grenade drag, choose targets, lengthen actual
shots, change missile steering, or grant additional weapon charges. The ordinary
short guide returns when Scope ends. Its icon uses the same drawing function in
the legend, rules editor and maze.


## Laser

The pink laser has a total range budget of **2 × (maze width + maze height)**,
a 0.85-second cooldown, and three charges. It reflects off walls, including corner
hits, without refreshing that budget. The first vulnerable opponent stops the
beam; a shield absorbs the shot. It cannot hit its own shooter, even on a return
bounce. It does not pierce walls or tanks. The visible flash fades after 0.23
seconds, but damage happens once, immediately on firing. Tracing begins at the
tank centre; the first barrel-length segment is hidden but still counts toward
the range budget, preventing shots through cover when the barrel overlaps a wall.
Lasers do not occupy projectile slots, so existing shells do not prevent firing.
The server sends the complete reflected path for consistent visuals on all clients.

## Missiles and grenades

Missiles seek visible vulnerable opponents within ten cells and a wide seeker
cone, retaining the lock while valid. Steering is limited to **4.8 radians/second**;
the seeker threshold is `dot >= -0.75`, about 139 degrees either side. This is
more aggressive than v3.0, not guaranteed to be dodged by a simple sideways move.
Cover breaks line of sight. A lost lock coasts for 0.06 seconds before reacquiring;
a wall bounce preserves its reflected heading for 0.04 seconds.
It does not steer toward the launcher, but colliding with its own launcher after
the brief 0.2-second launch grace can still cause damage. Shields absorb a hit.

Missiles **bounce off walls and corners**, not through them. The whole flight has
one range budget of **maze width + maze height**, half of the maze perimeter.
The barrel segment, curved movement, ricochets, and collision-separation nudges all
spend that budget; bounces and target changes never refill it. The missile expires
at the distance limit, including partway through a simulation tick. In the default
12×10 maze this budget is 1,848 world units. Speed remains 235 units/second.
There is also a defensive lifetime of `budget / 235 + 0.5` seconds and a 128-bounce
safety ceiling. A hit or round reset can end flight sooner. The weapon still equips
three missiles for 10/15 seconds; this equip timer is separate from missile flight.

Press Fire to throw a grenade, release, and press Fire again to detonate early.
Holding never auto-detonates or launches another grenade. The fallback fuse is
**ten seconds**. The next press detonates owned live grenades even after the last
charge, equip timer expiry, or a new weapon pickup; no extra charge is consumed.
Detonation works during the launch cooldown and only for a living owner. The HUD
shows DETONATE and the mobile button changes to BOOM while a grenade is active.

Grenades detonate on living-tank contact, including stationary overlap. They produce one blast rather than a separate contact hit plus blast. Their explosion can
hit multiple tanks, including the thrower, within a 110-world-unit radius against
tank circles. A wall-visibility check to each tank center blocks covered targets.
A living teammate or invulnerable tank can also trigger the explosion, but existing
friendly-fire and invulnerability rules still prevent their damage. The thrower
has a 0.2-second launch grace; wrecks do not trigger contact. Shields absorb one
blast, not a separate contact hit followed by another blast. Grenades do not
destroy walls. The fuse is shown as a ring.

## Stacking, HUD, and expiry

A new weapon replaces the current weapon. **Speed, Shield, Scope and Ghost are independent**
and can coexist with one another and any weapon. Another Speed pickup adds one stack up to five and refreshes the shared six-second timer.
Speed does not increase projectile speed. Ghost independently allows internal-wall
movement; even with both buffs, the outer rim remains solid. All powers reset for the next round.

For normal/missile/grenade/Cannon weapons, ammunition bars show available active
projectile slots; special-weapon charges and timers are shown separately. The
laser instead shows its three remaining charges in the bars. Already launched
projectiles retain their lifetime after the weapon expires. Three-shot weapons
are removed after the last charge or their 10/15-second equip timer, whichever
comes first.

## Bots and online ownership

Bots may collect all ten types and pursue opponents according to the room's
teams. Their shots, lasers and blasts follow the host’s friendly-fire setting;
with it off, teammates and friendly shields are protected. Normal/Fierce bots can plan bank shots and evasive routes; bots can
remotely detonate a grenade against an exposed opponent.

Go controls all online grants, timers, missile locks, fuses, laser hits, damage,
and scoring. Client movement prediction uses the same speed, Ghost and safe-expiry rules. Beam
and explosion effects are cosmetic, generation-scoped, and cannot award damage.

Current upgrade instructions and test limitations: **UPDATE-v4.1.md** and **TESTING.md**.

## Matching legend icons

All ten legend icons use the very same `powerIcon` Canvas drawing routine,
colors, stroke thickness, and orientation as their maze pickups. The legend no
longer uses lookalike text glyphs. Its small canvases are rendered at device pixel
ratio and redrawn when layout changes; the adjacent labels supply readable names.

## Teams and bot controllers

All weapons respect the room's assigned sides. Friendly-fire off protects other
same-team tanks and their shields; on allows teammate damage. Bots deliberately
target opponents in either setting. Self-damage is separate from friendly fire,
with the existing launch grace and laser shooter immunity unchanged. Each local
keyboard pilot has independent Fire and grenade-detonation controls in local
and shared rooms. The default lineup remains one human and three Normal bots
in Free-for-all.
