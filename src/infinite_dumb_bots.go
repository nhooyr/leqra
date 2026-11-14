package main

import (
	"math"
	"slices"
	"strconv"
)

const (
	publicGodlikeLifeInterval = 64
	publicNormalLifeInterval  = 16
	publicPlayersPerGodlike   = 16
	dumbBotThinkTicks         = 54
	dumbBotShotTicks          = 108
)

// A bot's difficulty belongs to its identity. Ambient spawn opportunities pick
// a tier before selecting an inactive identity; respawning never changes it.
func (a *infiniteArena) startBotLife(p *infinitePilot) {
	a.resetBotDecisions(p)
	if a.rules == nil && p.roomBot == nil && p.ambientNumber == 0 {
		p.botLevel = a.chooseAmbientBotLevel()
	}
	p.publicBotName()
	a.recordGodlikeSpawn(p)
}

func (a *infiniteArena) chooseAmbientBotLevel() int {
	if a.rules != nil {
		return a.chooseRoomBotLevel()
	}
	a.publicBotLives++
	if a.publicBotLives%publicGodlikeLifeInterval == 0 && a.livingPublicGodlikes(nil) < a.publicGodlikeLimit() {
		return infiniteBotLevel("godlike")
	} else if a.publicBotLives%publicNormalLifeInterval == publicNormalLifeInterval/2 {
		// Stagger Medium lives between Godlike slots so neither rarity
		// consumes the other's opportunity.
		return infiniteBotLevel("normal")
	}
	return infiniteBotLevel("dumb")
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
	for _, other := range a.pilots {
		if other != except && publicGodlike(other) {
			count++
		}
	}
	return count
}

// Retain visible encounters first. Excess bosses wait for another Godlike
// opportunity without changing their identity, difficulty, or earned score.
func (a *infiniteArena) enforcePublicGodlikeLimit() {
	if a.rules != nil {
		return
	}
	remaining := a.publicGodlikeLimit()
	for pass := 0; pass < 2; pass++ {
		for i := len(a.pilots) - 1; i >= 0; i-- {
			p := a.pilots[i]
			if !publicGodlike(p) || a.outsideActiveViews(p) != (pass == 1) {
				continue
			}
			if remaining > 0 {
				remaining--
				continue
			}
			a.godlikeSpawns = slices.DeleteFunc(a.godlikeSpawns, func(event infiniteGodlikeSpawn) bool { return event.ID == p.ID })
			a.parkAmbientBot(i)
		}
	}
}

func (p *infinitePilot) publicBotName() {
	if p.ambientNumber == 0 {
		return
	}
	p.Name = "Bot " + strconv.Itoa(p.ambientNumber)
	switch infiniteBotTunings[p.botLevel].name {
	case "godlike":
		p.Name += " - Godlike"
	case "normal":
		p.Name += " - Medium"
	default:
		p.Name += " - Dumb"
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
