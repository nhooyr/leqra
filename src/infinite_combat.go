package main

import (
	"math"
	"slices"
)

// Infinity uses a local encounter radius where finite modes use map dimensions.
// The weapon durations and other limits still bound work in an endless maze.
const (
	infinitePowerDuration = 15.0
	infiniteStarDuration  = 8.0
	infiniteShotRange     = 18 * cellSize
	infinitePickupLife    = 30.0
)

type infiniteEffect struct {
	ID     int         `json:"id"`
	Kind   string      `json:"kind"`
	X      float64     `json:"x"`
	Y      float64     `json:"y"`
	Owner  int         `json:"owner"`
	Points []BeamPoint `json:"points,omitempty"`
	tick   uint64
}

func (a *infiniteArena) effect(kind string, x, y float64, owner int, points []BeamPoint) {
	a.effectID++
	if len(a.effects) == 48 {
		a.effects = slices.Delete(a.effects, 0, 1)
	}
	a.effects = append(a.effects, infiniteEffect{a.effectID, kind, x, y, owner, points, a.tick})
}

func (p *infinitePilot) wireTank(tick uint64) infiniteTank {
	t, k := p.infiniteTank, &p.kit
	if p.Bot {
		t.Difficulty = infiniteBotTunings[p.botLevel].name
	} else {
		t.Difficulty = ""
	}
	t.X, t.Y, t.Angle = infinitePrecision(t.X), infinitePrecision(t.Y), infinitePrecision(t.Angle)
	t.VX, t.VY = infinitePrecision(t.VX), infinitePrecision(t.VY)
	if p.HP == 0 || p.disconnected || p.paused {
		t.VX, t.VY = 0, 0
	}
	t.Track, t.Recoil, t.Invuln = infinitePrecision(t.Track), infinitePrecision(k.Recoil), infinitePrecision(k.Invulnerable)
	t.SpawnProtected = k.SpawnProtected && k.Invulnerable > 1e-9
	t.Cooldown = infinitePrecision(k.Cooldown)
	if t.Cooldown > 0 {
		t.CooldownTotal = infinitePrecision(k.CooldownTotal)
	}
	if p.HP == 0 && p.respawn > tick {
		t.RespawnTime = infinitePrecision(float64(p.respawn-tick) * tickDT)
	}
	t.Power, t.PowerTime, t.Charges, t.Machine = k.Power, infinitePrecision(k.PowerTime), k.Charges, k.MachineRounds
	t.Shield, t.Shields = infinitePrecision(k.Shield), k.ShieldCharges
	t.SpeedTime, t.Speed = infinitePrecision(k.SpeedTime), k.SpeedStacks
	t.Ghost, t.Starman = infinitePrecision(k.GhostTime), infinitePrecision(k.StarmanTime)
	return t
}

func infinitePrecision(value float64) float64 { return math.Round(value*1000) / 1000 }

func (a *infiniteArena) advanceEquipment(p *infinitePilot) {
	k := &p.kit
	k.Invulnerable = max(0, k.Invulnerable-tickDT)
	if k.Invulnerable <= 1e-9 {
		k.SpawnProtected = false
	}
	p.Protected = k.Invulnerable > 1e-9
	k.Shield = max(0, k.Shield-tickDT)
	if k.Shield < 1e-9 {
		k.Shield, k.ShieldCharges = 0, 0
	}
	k.StarmanTime = max(0, k.StarmanTime-tickDT)
	k.SpeedTime = max(0, k.SpeedTime-tickDT)
	if k.SpeedTime < 1e-9 {
		k.SpeedTime, k.SpeedStacks = 0, 0
	}
	wasGhost := k.GhostTime > 0
	k.GhostTime = max(0, k.GhostTime-tickDT)
	if k.GhostTime < 1e-9 {
		k.GhostTime = 0
		if wasGhost {
			p.X, p.Y = a.phaseExit(p.X, p.Y)
			p.hasWaypoint = false
		}
	}
	if k.StarmanTime <= 0 {
		k.PowerTime = max(0, k.PowerTime-tickDT)
		if k.PowerTime < 1e-9 {
			k.Power, k.PowerTime, k.Charges, k.MachineRounds = "", 0, 0, 0
		}
	}
	k.Cooldown = max(0, k.Cooldown-tickDT)
	k.Recoil = max(0, k.Recoil-9*tickDT)
}

// Any overlapping wall is in the current or adjacent cell. Each cell has a
// safe interior even when both boundary segments meet at a corner.
func (a *infiniteArena) phaseExit(x, y float64) (float64, float64) {
	if !a.maze.blocked(x, y, tankRadius) {
		return x, y
	}
	cx, cy := infiniteCell(x, y)
	const margin = wallSize/2 + tankRadius + .01
	best, bestX, bestY := math.Inf(1), x, y
	for row := cy - 1; row <= cy+1; row++ {
		for col := cx - 1; col <= cx+1; col++ {
			xx := clamp(x, float64(col)*cellSize+margin, float64(col+1)*cellSize-margin)
			yy := clamp(y, float64(row)*cellSize+margin, float64(row+1)*cellSize-margin)
			if distance := math.Hypot(xx-x, yy-y); distance < best-1e-8 {
				best, bestX, bestY = distance, xx, yy
			}
		}
	}
	return bestX, bestY
}

func (a *infiniteArena) populatePickups() {
	for i := range a.pickups {
		a.pickups[i].Age += tickDT
		a.pickups[i].Life -= tickDT
	}
	a.pickups = slices.DeleteFunc(a.pickups, func(p Pickup) bool { return p.Life <= 0 })
	if a.tick < a.nextPickup {
		return
	}
	a.nextPickup = a.tick + uint64(75+a.random.IntN(76))
	a.pickups = slices.DeleteFunc(a.pickups, func(p Pickup) bool {
		for _, pilot := range a.pilots {
			if !pilot.Bot && math.Hypot(pilot.X-p.X, pilot.Y-p.Y) < cellSize*11 {
				return false
			}
		}
		return true
	})
	for _, p := range a.pilots {
		if p.Bot || p.HP == 0 {
			continue
		}
		nearby := 0
		for _, pickup := range a.pickups {
			if math.Hypot(p.X-pickup.X, p.Y-pickup.Y) < cellSize*5 {
				nearby++
			}
		}
		for nearby < 3 && len(a.pickups) < a.players*6 {
			if !a.spawnPickup(p) {
				break
			}
			nearby++
		}
	}
}

func (a *infiniteArena) spawnPickup(p *infinitePilot) bool {
	cx, cy := infiniteCell(p.X, p.Y)
	for range 30 {
		dx, dy := a.random.IntN(7)-3, a.random.IntN(7)-3
		if dx*dx+dy*dy > 12 {
			continue
		}
		x, y := infiniteCenter(cx+dx, cy+dy)
		if slices.ContainsFunc(a.pilots, func(t *infinitePilot) bool {
			return t.HP > 0 && math.Hypot(t.X-x, t.Y-y) < .85*cellSize
		}) || slices.ContainsFunc(a.pickups, func(q Pickup) bool {
			return math.Hypot(q.X-x, q.Y-y) < 1.1*cellSize
		}) {
			continue
		}
		total := 0
		for _, kind := range pickupTypes {
			total += pickupWeight(kind)
		}
		choice := a.random.IntN(total)
		for _, kind := range pickupTypes {
			choice -= pickupWeight(kind)
			if choice < 0 {
				a.pickupID++
				a.pickups = append(a.pickups, Pickup{ID: a.pickupID, X: x, Y: y, Type: kind, Life: infinitePickupLife})
				return true
			}
		}
	}
	return false
}

func (a *infiniteArena) collectPickup(p *infinitePilot) {
	for i := range a.pickups {
		pickup := &a.pickups[i]
		if pickup.Life > 0 && math.Hypot(pickup.X-p.X, pickup.Y-p.Y) < tankRadius+13 {
			pickup.Life = 0
			applyPower(&p.kit, pickup.Type, infinitePowerDuration, infiniteStarDuration)
			if p.Bot && pickup.Type == "grenade" {
				p.kit.fireHeld = false
			}
			p.Protected = p.kit.Invulnerable > 0
			a.effect("pickup", p.X, p.Y, p.ID, nil)
		}
	}
}

type infiniteProjectileSpec struct {
	speed, radius, life, cooldown float64
}

func infiniteSpec(kind string) infiniteProjectileSpec {
	switch kind {
	case "rapid":
		return infiniteProjectileSpec{machineSpeed, machineRadius, infiniteShotRange / machineSpeed, 0}
	case "scatter":
		return infiniteProjectileSpec{shotgunSpeed, regularRadius, 3.9, .54}
	case "homing":
		return infiniteProjectileSpec{missileSpeed, 5, infiniteShotRange / missileSpeed, .72}
	case "grenade":
		return infiniteProjectileSpec{grenadeSpeed, 6, grenadeFuse, .8}
	case "cannon":
		return infiniteProjectileSpec{cannonSpeed, cannonRadius, cannonLifetime, cannonCooldown}
	default:
		return infiniteProjectileSpec{regularSpeed, regularRadius, 5.3, .34}
	}
}

func (a *infiniteArena) weaponControl(p *infinitePilot, held, pressed bool) {
	k := &p.kit
	k.fireHeld = held
	if !held {
		k.fireBlocked = false
	}
	if k.SpawnProtected && k.Invulnerable > 1e-9 {
		return
	}
	if pressed {
		detonated := false
		for i := range a.bullets {
			b := &a.bullets[i]
			if b.Owner == p.ID && b.Kind == "grenade" && !b.dead {
				a.detonate(b)
				detonated = true
			}
		}
		if detonated {
			k.fireBlocked = held
			return
		}
		if k.Power == "grenade" {
			k.fireBlocked = held
			a.fire(p)
			return
		}
	}
	if !k.fireBlocked && k.Power != "grenade" && (held || pressed) {
		a.fire(p)
	}
}

func (a *infiniteArena) projectileLaunch(p *infinitePilot, angle, radius, muzzle float64) projectileLaunch {
	ux, uy := math.Cos(angle), math.Sin(angle)
	if p.kit.Power == "cannon" || p.kit.GhostTime <= 0 {
		return projectileLaunch{x: p.X, y: p.Y, ux: ux, uy: uy, muzzle: muzzle, valid: true}
	}
	var storage [32]Wall
	walls := storage[:0]
	a.maze.visitWalls(p.X-radius-32, p.Y-radius-32, p.X+radius+32, p.Y+radius+32, func(w Wall) bool {
		walls = append(walls, w)
		return false
	})
	return wallLaunch(p.X, p.Y, ux, uy, radius, muzzle, walls, nil)
}

func (a *infiniteArena) fire(p *infinitePilot) {
	k := &p.kit
	starman := k.StarmanTime > 0
	if p.HP == 0 || k.SpawnProtected && k.Invulnerable > 1e-9 || !starman && (k.Cooldown > 1e-9 || k.Power == "rapid" && k.MachineRounds == 0) {
		return
	}
	kind := k.Power
	spec := infiniteSpec(kind)
	if kind == "laser" {
		spec.radius = laserRadius
	}
	if kind == "laser" {
		a.fireLaser(p)
		return
	}
	offsets := []float64{0}
	if kind == "scatter" {
		offsets = []float64{-.21, 0, .21}
	}
	ordinary, boosted := 0, 0
	if starman {
		spec.cooldown = 0
	} else {
		for _, b := range a.bullets {
			if !b.dead && b.Owner == p.ID {
				if b.boosted {
					boosted++
				} else {
					ordinary++
				}
			}
		}
		if capacity(k)-ordinary < len(offsets) {
			return
		}
	}
	k.ShotSerial++
	k.Cooldown, k.CooldownTotal, k.Recoil = spec.cooldown, spec.cooldown, 1
	before := len(a.bullets)
	for _, offset := range offsets {
		angle := p.Angle + offset
		muzzle := 28.0
		if kind == "cannon" {
			muzzle = tankRadius + spec.radius + 1
		}
		launch := a.projectileLaunch(p, angle, spec.radius, muzzle)
		if !launch.valid {
			a.effect("impact", p.X, p.Y, p.ID, nil)
			continue
		}
		a.nextBullet++
		b := infiniteBullet{ID: a.nextBullet, Owner: p.ID, ownerTeam: p.Team, ownerName: p.Name, X: launch.x, Y: launch.y, Kind: kind, Color: p.ColorIndex,
			VX: launch.ux * spec.speed, VY: launch.uy * spec.speed, Life: spec.life, radius: spec.radius, boosted: starman}
		if launch.bounced {
			b.Bounces = 1
			b.seekDelay = missileWallDelay
		}
		if a.advanceBullet(&b, launch.ux*launch.muzzle, launch.uy*launch.muzzle) {
			a.bullets = append(a.bullets, b)
		}
	}
	audible := kind != "rapid" || k.MachineRounds%4 == 0
	if starman && kind != "grenade" {
		audible = k.ShotSerial%4 == 1
	}
	if audible {
		a.effect("shot:"+kind, p.X, p.Y, p.ID, nil)
	}
	spawned := len(a.bullets) - before
	if starman || ordinary+boosted+spawned > machineCapacity {
		remaining := machineCapacity
		if !starman {
			remaining -= ordinary + spawned
		}
		for i := len(a.bullets) - 1; i >= 0; i-- {
			b := &a.bullets[i]
			if b.Owner != p.ID || b.dead || !starman && !b.boosted {
				continue
			}
			b.dead = remaining == 0
			remaining = max(0, remaining-1)
		}
	}
	a.spendWeapon(k)
}

func (a *infiniteArena) spendWeapon(k *Tank) {
	if k.StarmanTime > 0 {
		return
	}
	switch k.Power {
	case "":
		return
	case "rapid":
		k.MachineRounds--
		if k.MachineRounds > 0 {
			return
		}
	default:
		k.Charges--
		if k.Charges > 0 {
			return
		}
	}
	k.Power, k.PowerTime, k.Charges = "", 0, 0
}

func (a *infiniteArena) fireLaser(p *infinitePilot) {
	k := &p.kit
	if p.HP == 0 || k.SpawnProtected && k.Invulnerable > 1e-9 {
		return
	}
	k.ShotSerial++
	starman := k.StarmanTime > 0
	cooldown := laserCooldown
	if starman {
		cooldown = 0
	}
	k.Cooldown, k.CooldownTotal, k.Recoil = cooldown, cooldown, 1
	points, target := a.traceLaser(p)
	if !starman || k.ShotSerial%4 == 1 {
		a.effect("laser", p.X, p.Y, p.ID, points)
	}
	if target != nil {
		a.hurt(target, p.ID, p.Team, p.Name)
	}
	a.spendWeapon(k)
}

func (a *infiniteArena) traceLaser(p *infinitePilot) ([]BeamPoint, *infinitePilot) {
	launch := a.projectileLaunch(p, p.Angle, laserRadius, 28)
	if !launch.valid {
		return []BeamPoint{{p.X, p.Y}, {p.X, p.Y}}, nil
	}
	x, y, ux, uy := launch.x, launch.y, launch.ux, launch.uy
	points := make([]BeamPoint, 0, 12)
	remaining := infiniteShotRange - launch.distance
	for i := 0; i < laserMaxSegments && remaining > 1e-7; i++ {
		dx, dy := ux*remaining, uy*remaining
		wall, hasWall := a.rayWalls(x, y, dx, dy, laserRadius)
		stop := 1.0
		if hasWall {
			stop = wall.T
		}
		target, stop := a.hitTarget(p.ID, p.Team, x, y, dx, dy, laserRadius, stop, false)
		length := remaining * stop
		if i == 0 {
			muzzle := min(28, length)
			if launch.bounced {
				muzzle = 0
			}
			points = append(points, BeamPoint{x + ux*muzzle, y + uy*muzzle})
		}
		x, y = x+ux*length, y+uy*length
		points = append(points, BeamPoint{x, y})
		remaining -= length
		if target != nil || !hasWall || remaining <= 1e-7 {
			return points, target
		}
		if wall.NX != 0 {
			ux = -ux
		}
		if wall.NY != 0 {
			uy = -uy
		}
		nudge := min(.001, remaining)
		x, y = x+ux*nudge, y+uy*nudge
		remaining -= nudge
	}
	return points, nil
}

func infiniteOpposes(owner, team int, target *infinitePilot) bool {
	return owner != target.ID && (team == 0 || team != target.Team)
}

func (a *infiniteArena) canDamage(owner, team int, target *infinitePilot) bool {
	return owner != target.ID && (infiniteOpposes(owner, team, target) || a.rules != nil && a.rules.FriendlyFire)
}

func (a *infiniteArena) hitTarget(owner, ownerTeam int, x, y, dx, dy, radius, limit float64, contact bool) (*infinitePilot, float64) {
	var target *infinitePilot
	r := tankRadius + radius
	minX, maxX := min(x, x+dx)-r, max(x, x+dx)+r
	minY, maxY := min(y, y+dy)-r, max(y, y+dy)+r
	for _, p := range a.pilots {
		if p.X < minX || p.X > maxX || p.Y < minY || p.Y > maxY ||
			p.ID == owner || p.HP == 0 || !contact && (p.Protected || !a.canDamage(owner, ownerTeam, p)) {
			continue
		}
		if hit, ok := circleHit(x, y, dx, dy, p.X, p.Y, r); ok && hit < limit {
			limit, target = hit, p
		}
	}
	return target, limit
}

func (a *infiniteArena) hurt(target *infinitePilot, owner, ownerTeam int, ownerName string, ownerColor ...int) {
	if a.result != nil || target.HP == 0 || target.Protected || !a.canDamage(owner, ownerTeam, target) {
		return
	}
	k := &target.kit
	if k.Shield > 0 {
		k.ShieldCharges = shieldCount(k) - 1
		if k.ShieldCharges == 0 {
			k.Shield = 0
		}
		k.Invulnerable = .35
		k.SpawnProtected = false
		target.Protected = true
		a.effect("shield", target.X, target.Y, owner, nil)
		return
	}
	a.eliminatePilot(target, owner, ownerTeam, ownerName, ownerColor...)
}

func (a *infiniteArena) resolveStarmanContacts(actors []*infinitePilot) {
	for i := range actors {
		attacker := actors[(a.tick+uint64(i))%uint64(len(actors))]
		if attacker.HP == 0 || attacker.kit.StarmanTime <= 0 {
			continue
		}
		for _, target := range actors {
			if target.HP == 0 || target.Protected && !target.kit.SpawnProtected || target.kit.StarmanTime > 0 || !a.canDamage(attacker.ID, attacker.Team, target) {
				continue
			}
			dx, dy := target.X-attacker.X, target.Y-attacker.Y
			if dx*dx+dy*dy > 4*tankRadius*tankRadius {
				continue
			}
			if a.maze.visitWalls(min(attacker.X, target.X), min(attacker.Y, target.Y), max(attacker.X, target.X), max(attacker.Y, target.Y), func(w Wall) bool {
				return w.intersectsSegment(attacker.X, attacker.Y, dx, dy)
			}) {
				continue
			}
			a.eliminatePilot(target, attacker.ID, attacker.Team, attacker.Name)
			if a.result != nil {
				return
			}
		}
	}
}

func (a *infiniteArena) eliminatePilot(target *infinitePilot, owner, ownerTeam int, ownerName string, ownerColor ...int) {
	target.HP = 0
	target.VX, target.VY = 0, 0
	target.Score--
	target.respawn = a.tick + infiniteRespawnTicks
	target.KilledBy = ownerName
	target.KilledByColor = ""
	if len(ownerColor) > 0 && ownerColor[0] >= 0 && ownerColor[0] < len(tankColors) {
		target.KilledByColor = tankColors[ownerColor[0]]
	}
	a.effect("hit", target.X, target.Y, owner, nil)
	shooter := a.pilotByID(owner)
	if shooter != nil {
		shooter.Score++
		target.KilledBy = shooter.Name
		if shooter.ColorIndex >= 0 && shooter.ColorIndex < len(tankColors) {
			target.KilledByColor = tankColors[shooter.ColorIndex]
		}
	}
	if a.teams() {
		if target.Team > 0 {
			a.teamScores[target.Team-1]--
		}
		if ownerTeam > 0 {
			a.teamScores[ownerTeam-1]++
			score := a.teamScores[ownerTeam-1]
			if a.rules.Target > 0 && score >= a.rules.Target {
				a.result = &infiniteResult{Name: a.rules.TeamNames[ownerTeam-1], Team: ownerTeam, Score: score}
			}
		}
	} else if shooter != nil && a.rules != nil && a.rules.Target > 0 && shooter.Score >= a.rules.Target {
		a.result = &infiniteResult{ID: owner, Name: shooter.Name, Score: shooter.Score}
	}
}

func (a *infiniteArena) detonate(b *infiniteBullet) {
	b.dead = true
	a.effect("blast", b.X, b.Y, b.Owner, nil)
	for _, p := range a.pilots {
		if p.ID == b.Owner || p.HP == 0 || p.Protected || math.Hypot(p.X-b.X, p.Y-b.Y) > blastRadius+tankRadius {
			continue
		}
		if !a.rayBlocked(b.X, b.Y, p.X-b.X, p.Y-b.Y, 0) {
			a.hurt(p, b.Owner, b.ownerTeam, b.ownerName, b.Color)
		}
	}
}

func (a *infiniteArena) advanceBullet(b *infiniteBullet, dx, dy float64) bool {
	radius := b.radius
	if radius <= 0 {
		radius = regularRadius
	}
	for range 4 {
		nearest := 1.0 + 1e-8
		var wall RayHit
		hasWall := false
		if b.Kind != "cannon" {
			wall, hasWall = a.rayWalls(b.X, b.Y, dx, dy, radius)
		}
		if hasWall {
			nearest = wall.T
		}
		target, contact := a.hitTarget(b.Owner, b.ownerTeam, b.X, b.Y, dx, dy, radius, nearest, b.Kind == "grenade")
		if target != nil {
			b.X, b.Y = b.X+dx*contact, b.Y+dy*contact
			if b.Kind == "grenade" {
				a.detonate(b)
			} else {
				if b.Kind == "cannon" || b.Kind == "homing" {
					a.effect("impact", b.X, b.Y, b.Owner, nil)
				}
				a.hurt(target, b.Owner, b.ownerTeam, b.ownerName, b.Color)
			}
			return false
		}
		if !hasWall {
			b.X, b.Y = b.X+dx, b.Y+dy
			return true
		}
		b.Bounces++
		if b.Bounces > 128 || b.Bounces > 22 && b.Kind != "homing" && b.Kind != "rapid" && b.Kind != "grenade" {
			if b.Kind == "grenade" {
				a.detonate(b)
			}
			return false
		}
		b.X += dx*wall.T + wall.NX*.12
		b.Y += dy*wall.T + wall.NY*.12
		dx, dy = dx*(1-wall.T), dy*(1-wall.T)
		if wall.NX != 0 {
			dx, b.VX = -dx, -b.VX
		}
		if wall.NY != 0 {
			dy, b.VY = -dy, -b.VY
		}
		b.Target, b.seekDelay = 0, missileWallDelay
		if wall.T == 1 {
			return true
		}
	}
	return true
}

func (a *infiniteArena) guide(b *infiniteBullet, dt float64) {
	b.seekDelay = max(0, b.seekDelay-dt)
	if b.age < .1 || b.seekDelay > 0 {
		return
	}
	var target *infinitePilot
	best, speed := missileRange, math.Hypot(b.VX, b.VY)
	for _, p := range a.pilots {
		if !infiniteOpposes(b.Owner, b.ownerTeam, p) || p.HP == 0 || p.Protected || b.Target != 0 && p.ID != b.Target {
			continue
		}
		dx, dy := p.X-b.X, p.Y-b.Y
		d := math.Hypot(dx, dy)
		if d >= best || dx*b.VX+dy*b.VY < missileViewCos*d*speed {
			continue
		}
		if !a.rayBlocked(b.X, b.Y, dx, dy, b.radius) {
			best, target = d, p
		}
	}
	if target == nil {
		if b.Target != 0 {
			b.Target, b.seekDelay = 0, missileLockDelay
		}
		return
	}
	b.Target = target.ID
	angle := guidedProjectileAngle(math.Atan2(b.VY, b.VX), math.Atan2(target.Y-b.Y, target.X-b.X), dt)
	b.VX, b.VY = math.Cos(angle)*speed, math.Sin(angle)*speed
}

func (a *infiniteArena) advanceBullets() {
	live := a.bullets[:0]
	for _, b := range a.bullets {
		if b.dead {
			continue
		}
		if a.result != nil {
			live = append(live, b)
			continue
		}
		dt := min(tickDT, b.Life)
		b.age += dt
		b.Life -= dt
		if b.Kind == "homing" || b.Kind == "grenade" {
			a.guide(&b, dt)
		}
		if b.Kind == "grenade" {
			drag := grenadeDragFactor(b.Life+dt, b.Life)
			b.VX, b.VY = b.VX*drag, b.VY*drag
		}
		if a.advanceBullet(&b, b.VX*dt, b.VY*dt) {
			if b.Life > 1e-9 {
				live = append(live, b)
			} else if b.Kind == "grenade" {
				a.detonate(&b)
			}
		}
	}
	a.bullets = live
}
