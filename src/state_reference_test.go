package main

import (
	"math"
	"sort"
)

// Reference wire encoding retained for regression tests. Production builds
// encode both direct and periodic snapshots from stateWire.
func (h *Hub) stateMessage(r *Room) map[string]any {
	g := r.Game
	ts := make([]Tank, 0, maxTanks)
	bs := make([]Bullet, 0, len(g.Bullets))
	var boosted []int
	ms := make([][12]float64, 0, len(g.Bullets)) // Compact Machine gun records; same authoritative samples.
	ps := make([]Pickup, 0, len(g.Pickups))
	for _, t := range g.Tanks {
		if t == nil {
			continue
		}
		v := *t
		v.X = rounded(v.X)
		v.Y = rounded(v.Y)
		v.Angle = math.Round(v.Angle*10000) / 10000
		v.VX = rounded(v.VX)
		v.VY = rounded(v.VY)
		v.Cooldown = rounded(v.Cooldown)
		v.Invulnerable = rounded(v.Invulnerable)
		v.Shield = rounded(v.Shield)
		v.PowerTime = rounded(v.PowerTime)
		// SpeedTime stays full precision: input replay must match the exact expiry tick.
		v.Recoil = rounded(v.Recoil)
		v.Track = rounded(v.Track)
		ts = append(ts, v)
	}
	for _, b := range g.Bullets {
		v := *b
		if b.boosted && !b.Dead {
			boosted = append(boosted, b.ID)
		}
		v.X = rounded(v.X)
		v.Y = rounded(v.Y)
		v.VX = rounded(v.VX)
		v.VY = rounded(v.VY)
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		if v.Kind == "rapid" {
			color := tankColorIndex[v.Color]
			ms = append(ms, [12]float64{float64(v.ID), float64(v.Owner), float64(v.ShotSerial), float64(v.SpawnSerial), v.X, v.Y, v.VX, v.VY, v.Age, v.Life, float64(v.Bounces), float64(color)})
		} else {
			bs = append(bs, v)
		}
	}
	for _, p := range g.Pickups {
		v := *p
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		ps = append(ps, v)
	}
	events := append([]Event(nil), g.events...)
	for _, event := range g.projectileEvents {
		if event.Generation != g.Generation || g.Tick-event.Tick >= projectileEffectHistoryTicks {
			continue
		}
		duplicate := false
		for _, existing := range events {
			if existing.ID == event.ID {
				duplicate = true
				break
			}
		}
		if !duplicate {
			events = append(events, event)
		}
	}
	sort.Slice(events, func(i, j int) bool { return events[i].ID < events[j].ID })
	s := map[string]any{"type": "state", "tick": g.Tick, "generation": g.Generation, "phase": g.Phase, "phaseTime": rounded(g.PhaseTime), "round": g.Round, "roundClock": rounded(g.Clock), "winner": g.Winner, "scores": g.Scores, "tanks": ts, "bullets": bs, "pickups": ps, "events": events, "rules": g.settings(), "objectives": snapshotObjectives(g.Objectives)}
	if len(boosted) > 0 {
		s["boostedBulletIds"] = boosted
	}
	if len(ms) > 0 {
		s["machineBullets"] = ms
	}
	if g.Phase == "matchOver" && g.matchReportWire != nil {
		s["matchStats"] = g.matchReportWire
	}
	return s
}

// Read-only snapshots must not alias live wave counters or flag state.
func snapshotObjectives(o *ObjectiveState) *ObjectiveState {
	if o == nil {
		return nil
	}
	v := *o
	v.Flags = make([]*Flag, len(o.Flags))
	for i, f := range o.Flags {
		if f != nil {
			copyFlag := *f
			v.Flags[i] = &copyFlag
		}
	}
	if o.Survival != nil {
		s := *o.Survival
		v.Survival = &s
	}
	return &v
}
