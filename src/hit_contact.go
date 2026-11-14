package main

// Contact is presentation metadata. Damage, scores, respawn and input authority
// have already been resolved by the server when clients receive it.
type projectileContact struct {
	ProjectileID int              `json:"projectileId"`
	Kind         string           `json:"kind"`
	Tick         float64          `json:"tick"`
	Target       int              `json:"target"`
	SpawnSerial  int              `json:"spawnSerial"`
	Before       contactTankState `json:"before"`
}

type contactTankState struct {
	X              float64 `json:"x"`
	Y              float64 `json:"y"`
	Angle          float64 `json:"angle"`
	VX             float64 `json:"vx"`
	VY             float64 `json:"vy"`
	HP             int     `json:"hp"`
	Shield         float64 `json:"shield"`
	ShieldCharges  int     `json:"shieldCharges"`
	Invulnerable   float64 `json:"invulnerable"`
	SpawnProtected bool    `json:"spawnProtected"`
}

func tankContactBefore(t *Tank) contactTankState {
	hp := 0
	if t.Alive {
		hp = 1
	}
	return contactTankState{X: t.X, Y: t.Y, Angle: t.Angle, VX: t.VX, VY: t.VY, HP: hp,
		Shield: t.Shield, ShieldCharges: shieldCount(t), Invulnerable: t.Invulnerable, SpawnProtected: t.SpawnProtected}
}

func pilotContactBefore(p *infinitePilot) contactTankState {
	return contactTankState{X: p.X, Y: p.Y, Angle: p.Angle, VX: p.VX, VY: p.VY, HP: p.HP,
		Shield: p.kit.Shield, ShieldCharges: shieldCount(&p.kit), Invulnerable: p.kit.Invulnerable, SpawnProtected: p.kit.SpawnProtected}
}

func (g *Game) bulletContact(t *Tank, b *Bullet) *projectileContact {
	kind := b.Kind
	if kind == "" {
		kind = "regular"
	}
	at := float64(g.Tick)
	if b.ID > 0 && b.flightTracked {
		at = clamp(b.flightTick(), 0, float64(g.Tick))
	}
	return &projectileContact{ProjectileID: b.ID, Kind: kind, Tick: at, Target: t.ID, SpawnSerial: t.SpawnSerial, Before: tankContactBefore(t)}
}

func (g *Game) emitContact(kind string, t *Tank, owner int, text string, contact *projectileContact) {
	g.emit(kind, t, owner, text)
	if contact != nil {
		e := &g.events[len(g.events)-1]
		e.Contact = contact
		g.retainProjectileEvent(*e)
	}
}

func (a *infiniteArena) instantContact(target *infinitePilot, kind string) *projectileContact {
	return &projectileContact{Kind: kind, Tick: float64(a.tick), Target: target.ID, SpawnSerial: target.Spawn, Before: pilotContactBefore(target)}
}

func (a *infiniteArena) bulletContact(target *infinitePilot, b *infiniteBullet) *projectileContact {
	kind := b.Kind
	if kind == "" {
		kind = "regular"
	}
	contact := a.instantContact(target, kind)
	contact.ProjectileID = b.ID
	if b.ID > 0 && b.flightTracked {
		contact.Tick = clamp(b.flightTick(), 0, float64(a.tick))
	}
	return contact
}

func (a *infiniteArena) contactEffect(kind string, target *infinitePilot, owner int, contact *projectileContact) {
	a.effect(kind, target.X, target.Y, owner, nil)
	if contact != nil {
		e := &a.effects[len(a.effects)-1]
		e.Contact = contact
		a.retainProjectileEffect(*e)
	}
}

func (a *infiniteArena) hurtProjectile(target *infinitePilot, b *infiniteBullet) {
	a.hurtWithContact(target, b.Owner, b.ownerTeam, b.ownerName, a.bulletContact(target, b), b.Color)
}
