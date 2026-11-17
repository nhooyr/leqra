package main

import (
	"math"
	"sort"
)

// Each swept segment resolves all contacts in travel order. A shell may cross
// the same body again after bouncing, but damages each life only once.
func (g *Game) cannonSegment(b *Bullet, dx, dy, age, span float64) {
	var hits []struct {
		tank *Tank
		at   float64
	}
	for _, target := range g.Tanks {
		if target == nil || !target.Alive || target.Invulnerable > 0 || !g.canDamage(b.Owner, target) {
			continue
		}
		radius := target.R + b.R + 1e-7 // Keep floating-point grazing contacts in the narrow phase.
		if target.X < math.Min(b.X, b.X+dx)-radius || target.X > math.Max(b.X, b.X+dx)+radius || target.Y < math.Min(b.Y, b.Y+dy)-radius || target.Y > math.Max(b.Y, b.Y+dy)+radius {
			continue
		}
		if b.cannonHits != nil && (*b.cannonHits)[target.ID] == target.SpawnSerial+1 {
			continue
		}
		if at, ok := circleHit(b.X, b.Y, dx, dy, target.X, target.Y, target.R+b.R); ok && at <= 1 {
			hits = append(hits, struct {
				tank *Tank
				at   float64
			}{target, at})
		}
	}
	if len(hits) == 0 {
		return
	}
	if len(hits) > 1 {
		sort.SliceStable(hits, func(i, j int) bool { return hits[i].at < hits[j].at })
	}
	x, y := b.X, b.Y
	for _, hit := range hits {
		if b.cannonHits == nil {
			hits := make(map[int]int)
			b.cannonHits = &hits
		}
		(*b.cannonHits)[hit.tank.ID] = hit.tank.SpawnSerial + 1
		b.X, b.Y = x+dx*hit.at, y+dy*hit.at
		b.flightAge = age + span*hit.at
		g.projectileTankImpact(b, hit.tank)
	}
	b.X, b.Y = x, y
}

func (a *infiniteArena) cannonSegment(b *infiniteBullet, dx, dy, age, span float64) {
	var hits []struct {
		pilot *infinitePilot
		at    float64
	}
	radius := tankRadius + b.radius + 1e-7
	minX, maxX := math.Min(b.X, b.X+dx)-radius, math.Max(b.X, b.X+dx)+radius
	minY, maxY := math.Min(b.Y, b.Y+dy)-radius, math.Max(b.Y, b.Y+dy)+radius
	for _, target := range a.pilots {
		if target.HP == 0 || target.Protected || !a.canDamage(b.Owner, b.ownerTeam, target) {
			continue
		}
		if target.X < minX || target.X > maxX || target.Y < minY || target.Y > maxY {
			continue
		}
		if b.cannonHits != nil && (*b.cannonHits)[target.ID] == target.Spawn+1 {
			continue
		}
		if at, ok := circleHit(b.X, b.Y, dx, dy, target.X, target.Y, tankRadius+b.radius); ok && at <= 1 {
			hits = append(hits, struct {
				pilot *infinitePilot
				at    float64
			}{target, at})
		}
	}
	if len(hits) == 0 {
		return
	}
	if len(hits) > 1 {
		sort.SliceStable(hits, func(i, j int) bool { return hits[i].at < hits[j].at })
	}
	x, y := b.X, b.Y
	a.volleyDepth++
	for _, hit := range hits {
		if b.cannonHits == nil {
			hits := make(map[int]int)
			b.cannonHits = &hits
		}
		(*b.cannonHits)[hit.pilot.ID] = hit.pilot.Spawn + 1
		b.X, b.Y = x+dx*hit.at, y+dy*hit.at
		b.flightAge = age + span*hit.at
		a.effect("impact", b.X, b.Y, b.Owner, nil)
		a.hurtProjectile(hit.pilot, b)
	}
	a.volleyDepth--
	a.checkTargetResult(b.Owner, b.ownerTeam)
	b.X, b.Y = x, y
}
