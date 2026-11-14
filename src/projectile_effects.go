package main

import "slices"

const projectileEffectHistoryTicks = 36 // 600ms: covers ordinary 50–400ms queue jitter.
// Starman Shotgun can end three shots per actor per 60Hz tick: 108 terminal
// flights in 600ms. Leave room for their victim contacts and laser paths too.
const projectileEffectsPerActor = 128

// The ordinary cosmetic queues are intentionally small. Terminal flights and
// beam paths have separate bounded history so unrelated distant fire cannot
// evict a short lethal shot before its next visible snapshot.
func (g *Game) retainProjectileEvent(e Event) {
	if e.Flight == nil && e.Contact == nil && e.Type != "laser" {
		return
	}
	g.pruneProjectileEvents()
	g.projectileEvents = append(g.projectileEvents, e)
	if limit := maxTanks * projectileEffectsPerActor; len(g.projectileEvents) > limit {
		g.projectileEvents = slices.Delete(g.projectileEvents, 0, len(g.projectileEvents)-limit)
	}
}

func (g *Game) pruneProjectileEvents() {
	g.projectileEvents = slices.DeleteFunc(g.projectileEvents, func(e Event) bool {
		return e.Generation != g.Generation || g.Tick-e.Tick >= projectileEffectHistoryTicks
	})
}

func (g *Game) projectileSnapshotEvents(dst []Event) []Event {
	g.pruneProjectileEvents()
	if len(g.events) == 0 && len(g.projectileEvents) == 0 && g.events == nil {
		return nil
	}
	for i, j := 0, 0; i < len(g.events) || j < len(g.projectileEvents); {
		if j == len(g.projectileEvents) || i < len(g.events) && g.events[i].ID <= g.projectileEvents[j].ID {
			e := g.events[i]
			i++
			if j < len(g.projectileEvents) && e.ID == g.projectileEvents[j].ID {
				j++
			}
			dst = append(dst, e)
		} else {
			dst = append(dst, g.projectileEvents[j])
			j++
		}
	}
	return dst
}

func (a *infiniteArena) attachFlightEffect(b *infiniteBullet) {
	if flight := b.finishFlight(); flight != nil {
		e := &a.effects[len(a.effects)-1]
		e.Flight = flight
		a.retainProjectileEffect(*e)
	}
}

func (a *infiniteArena) retainProjectileEffect(e infiniteEffect) {
	if e.Flight == nil && e.Contact == nil && e.Kind != "laser" {
		return
	}
	a.pruneProjectileEffects()
	a.projectileEffects = append(a.projectileEffects, e)
	if limit := max(1, len(a.pilots)) * projectileEffectsPerActor; len(a.projectileEffects) > limit {
		a.projectileEffects = slices.Delete(a.projectileEffects, 0, len(a.projectileEffects)-limit)
	}
}

func (a *infiniteArena) pruneProjectileEffects() {
	a.projectileEffects = slices.DeleteFunc(a.projectileEffects, func(e infiniteEffect) bool {
		return a.tick-e.tick >= projectileEffectHistoryTicks
	})
}

func (a *infiniteArena) projectileSnapshotEffects(dst []infiniteEffect) []infiniteEffect {
	a.pruneProjectileEffects()
	for i, j := 0, 0; i < len(a.effects) || j < len(a.projectileEffects); {
		if j == len(a.projectileEffects) || i < len(a.effects) && a.effects[i].ID <= a.projectileEffects[j].ID {
			e := a.effects[i]
			i++
			if j < len(a.projectileEffects) && e.ID == a.projectileEffects[j].ID {
				j++
			}
			dst = append(dst, e)
		} else {
			dst = append(dst, a.projectileEffects[j])
			j++
		}
	}
	return dst
}
