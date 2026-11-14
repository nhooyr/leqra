package main

// A fast projectile can hit a nearby tank entirely between state broadcasts.
// Retain its authoritative visible path on a terminal cosmetic so rendering
// can recover that flight without inventing another damaging projectile.
type cannonFlightPoint struct {
	X    float64 `json:"x"`
	Y    float64 `json:"y"`
	Tick float64 `json:"tick"`
}

type cannonFlight struct {
	ID         int                 `json:"id"`
	Owner      int                 `json:"owner"`
	ColorIndex int                 `json:"colorIndex"`
	Kind       string              `json:"kind"`
	Radius     float64             `json:"radius"`
	StartTick  float64             `json:"startTick"`
	EndTick    float64             `json:"endTick"`
	Points     []cannonFlightPoint `json:"points"`
}

func newCannonFlight(id, owner, color int, kind string, radius, x, y, tick float64) *cannonFlight {
	if kind == "" {
		kind = "regular"
	}
	f := &cannonFlight{ID: id, Owner: owner, ColorIndex: color, Kind: kind, Radius: radius, Points: make([]cannonFlightPoint, 0, 4)}
	f.reset(x, y, tick)
	return f
}

func (f *cannonFlight) reset(x, y, tick float64) {
	f.StartTick, f.EndTick = tick, tick
	f.Points = append(f.Points[:0], cannonFlightPoint{x, y, tick})
}

func (f *cannonFlight) advance(x, y, tick float64, vertex bool) {
	if f == nil {
		return
	}
	if !vertex {
		return
	}
	at := max(f.StartTick, tick)
	if len(f.Points) == 32 {
		copy(f.Points[1:], f.Points[2:]) // Preserve birth and the latest contacts.
		f.Points = f.Points[:31]
	}
	f.Points = append(f.Points, cannonFlightPoint{x, y, at})
	f.EndTick = at
}

func (b *Bullet) beginFlight(x, y, tick float64) {
	b.flightBirth, b.flightTracked = cannonFlightPoint{x, y, max(0, tick)}, true
	b.flightBaseAge, b.flightAge = b.Age, b.Age
}

func (b *Bullet) flightTick() float64 {
	return b.flightBirth.Tick + max(0, b.flightAge-b.flightBaseAge)/tickDT
}

func (b *Bullet) ensureFlight() *cannonFlight {
	if !b.flightTracked {
		return nil
	}
	if b.flight == nil {
		p := b.flightBirth
		b.flight = newCannonFlight(b.ID, b.Owner, tankColorIndex[b.Color], b.Kind, b.R, p.X, p.Y, p.Tick)
	}
	return b.flight
}

func (b *Bullet) finishFlight() *cannonFlight {
	f := b.ensureFlight().finish(b.X, b.Y, b.flightTick())
	b.flightEmitted = f != nil
	return f
}

func (b *Bullet) publishFlight(ticks ...float64) {
	b.published = true
	if b.Kind != "cannon" {
		at := b.flightBirth.Tick + max(0, b.Age-b.flightBaseAge)/tickDT
		if len(ticks) > 0 {
			at = ticks[0]
		}
		b.beginFlight(b.X, b.Y, at)
		if b.flight != nil {
			b.flight.reset(b.X, b.Y, at)
		}
	}
}

func (b *infiniteBullet) beginFlight(x, y, tick float64) {
	b.flightBirth, b.flightTracked = cannonFlightPoint{x, y, max(0, tick)}, true
	b.flightBaseAge, b.flightAge = b.age, b.age
}

func (b *infiniteBullet) flightTick() float64 {
	return b.flightBirth.Tick + max(0, b.flightAge-b.flightBaseAge)/tickDT
}

func (b *infiniteBullet) ensureFlight() *cannonFlight {
	if !b.flightTracked {
		return nil
	}
	if b.flight == nil {
		p := b.flightBirth
		b.flight = newCannonFlight(b.ID, b.Owner, b.Color, b.Kind, b.radius, p.X, p.Y, p.Tick)
	}
	return b.flight
}

func (b *infiniteBullet) finishFlight() *cannonFlight {
	f := b.ensureFlight().finish(b.X, b.Y, b.flightTick())
	b.flightEmitted = f != nil
	return f
}

func (b *infiniteBullet) publishFlight(ticks ...float64) {
	b.published = true
	if b.Kind != "cannon" {
		at := b.flightBirth.Tick + max(0, b.age-b.flightBaseAge)/tickDT
		if len(ticks) > 0 {
			at = ticks[0]
		}
		b.beginFlight(b.X, b.Y, at)
		if b.flight != nil {
			b.flight.reset(b.X, b.Y, at)
		}
	}
}

func (f *cannonFlight) finish(x, y, tick float64) *cannonFlight {
	if f != nil {
		f.advance(x, y, tick, true)
	}
	return f
}
