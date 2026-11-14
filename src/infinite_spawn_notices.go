package main

import (
	"math"
	"slices"
	"time"
)

const godlikeSpawnNoticeTTL = 8 * time.Second
const godlikeSpawnNoticeRange = 12 * cellSize

type infiniteGodlikeSpawn struct {
	ID    int    `json:"id"`
	Spawn int    `json:"spawnSerial"`
	Name  string `json:"name"`
	at    time.Time
	x, y  float64
}

func (a *infiniteArena) spawnNoticeTime() time.Time {
	if !a.clock.IsZero() {
		return a.clock
	}
	return time.Now()
}

func (a *infiniteArena) pruneGodlikeSpawns(now time.Time) {
	a.godlikeSpawns = slices.DeleteFunc(a.godlikeSpawns, func(event infiniteGodlikeSpawn) bool { return now.Sub(event.at) >= godlikeSpawnNoticeTTL })
}

// Called at a true birth only. Coordinates and time describe that birth even
// if the existing body later relocates or returns from the inactive pool.
func (a *infiniteArena) recordGodlikeSpawn(p *infinitePilot) {
	if a.rules != nil || !publicGodlike(p) || p.ambientNumber == 0 {
		return
	}
	now := a.spawnNoticeTime()
	a.pruneGodlikeSpawns(now)
	for _, event := range a.godlikeSpawns {
		if event.ID == p.ID && event.Spawn == p.Spawn {
			return
		}
	}
	if len(a.godlikeSpawns) >= infiniteBotLimit {
		a.godlikeSpawns = slices.Delete(a.godlikeSpawns, 0, 1)
	}
	a.godlikeSpawns = append(a.godlikeSpawns, infiniteGodlikeSpawn{ID: p.ID, Spawn: p.Spawn, Name: p.Name, at: now, x: p.X, y: p.Y})
}

func (p *infinitePilot) nearGodlikeSpawn(event infiniteGodlikeSpawn, now time.Time) bool {
	age := now.Sub(event.at)
	if age < 0 || age >= godlikeSpawnNoticeTTL {
		return false
	}
	if math.Hypot(event.x-p.X, event.y-p.Y) <= godlikeSpawnNoticeRange {
		return true
	}
	return p.local != nil && math.Hypot(event.x-p.local.X, event.y-p.local.Y) <= godlikeSpawnNoticeRange
}
