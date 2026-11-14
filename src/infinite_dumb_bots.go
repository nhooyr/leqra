package main

import (
	"math"
	"strconv"
)

const (
	publicGodlikeLifeInterval = 64
	publicPlayersPerGodlike   = 16
	dumbBotThinkTicks         = 54
	dumbBotShotTicks          = 108
)

// A true birth/respawn advances the public encounter cadence. Moving an alive
// bot near a viewer or reactivating its pooled identity is still the same life.
func (a *infiniteArena) startBotLife(p *infinitePilot) {
	a.resetBotDecisions(p)
	if a.rules != nil || p.roomBot != nil {
		return
	}
	a.publicBotLives++
	p.botLevel = infiniteBotLevel("dumb")
	if a.publicBotLives%publicGodlikeLifeInterval == 0 && a.livingPublicGodlikes(p) < a.publicGodlikeLimit() {
		p.botLevel = infiniteBotLevel("godlike")
	}
	p.publicBotName()
}

func (a *infiniteArena) publicGodlikeLimit() int {
	if a.connected <= 0 {
		return 0
	}
	return 1 + (a.connected-1)/publicPlayersPerGodlike
}

func (a *infiniteArena) resetBotDecisions(p *infinitePilot) {
	p.botThink, p.botShot = a.tick, a.tick+dumbBotShotTicks
	p.botAim, p.botTarget, p.botHasAim = 0, 0, false
}

func publicGodlike(p *infinitePilot) bool {
	return p.Bot && p.roomBot == nil && p.HP > 0 && infiniteBotTunings[p.botLevel].name == "godlike"
}

func (a *infiniteArena) livingPublicGodlikes(except *infinitePilot) int {
	count := 0
	for _, pilots := range [2][]*infinitePilot{a.pilots, a.inactiveBots} {
		for _, other := range pilots {
			if other != except && publicGodlike(other) {
				count++
			}
		}
	}
	return count
}

// Retain visible encounters first, then other active bodies, then the pool.
// Population changes never need to kill a boss or alter its earned score.
func (a *infiniteArena) enforcePublicGodlikeLimit() {
	if a.rules != nil {
		return
	}
	remaining := a.publicGodlikeLimit()
	for pass := 0; pass < 3; pass++ {
		pilots := a.pilots
		if pass == 2 {
			pilots = a.inactiveBots
		}
		for _, p := range pilots {
			if !publicGodlike(p) || pass < 2 && a.outsideActiveViews(p) != (pass == 1) {
				continue
			}
			if remaining > 0 {
				remaining--
				continue
			}
			p.botLevel = infiniteBotLevel("dumb")
			p.publicBotName()
			p.clearControls()
			a.resetBotDecisions(p)
		}
	}
}

func (p *infinitePilot) publicBotName() {
	if p.ambientNumber == 0 {
		return
	}
	p.Name = "Bot " + strconv.Itoa(p.ambientNumber)
	if infiniteBotTunings[p.botLevel].name == "godlike" {
		p.Name = "Godlike " + p.Name
	}
}

// Dumb bots notice opponents slowly, sometimes decline the encounter, and keep
// aiming at an inaccurate old position. A larger firing cone alone would let
// the ordinary perfect-tracking AI shoot sooner instead of making it easier.
func (a *infiniteArena) dumbBotInput(p *infinitePilot, sight, roam, aim float64) Input {
	if a.tick >= p.botThink {
		p.botThink = a.tick + dumbBotThinkTicks
		p.botHasAim, p.botTarget = false, 0
		if target := a.nearestPilot(p, cellSize*8*sight, true); target != nil {
			dx, dy := target.X-p.X, target.Y-p.Y
			if !a.rayBlocked(p.X, p.Y, dx, dy, infiniteBulletRadius) && a.random.Float64() >= .35 {
				p.botAim = math.Atan2(dy, dx) + (a.random.Float64()*2-1)*.6
				p.botTarget, p.botHasAim = target.ID, true
			}
		}
	}
	if p.botHasAim {
		target := a.pilotByID(p.botTarget)
		if target != nil && target.HP > 0 && infiniteOpposes(p.ID, p.Team, target) &&
			math.Hypot(target.X-p.X, target.Y-p.Y) < cellSize*8*sight &&
			!a.rayBlocked(p.X, p.Y, target.X-p.X, target.Y-p.Y, infiniteBulletRadius) {
			fire := a.tick >= p.botShot && !target.Protected && !p.kit.fireBlocked && math.Abs(delta(p.Angle, p.botAim)) < .12*aim
			if fire {
				p.botShot = a.tick + dumbBotShotTicks
			}
			return Input{StickX: math.Cos(p.botAim), StickY: math.Sin(p.botAim), AimOnly: true, Fire: fire}
		}
	}
	return a.botRoam(p, nil, roam)
}
