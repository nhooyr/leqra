package main

import (
	"encoding/json"
	"math"
	"testing"
)

func blastCount(g *Game) int {
	n := 0
	for _, e := range g.events {
		if e.Type == "blast" {
			n++
		}
	}
	return n
}
func impactGrenade(g *Game, x, y, vx float64) *Bullet {
	b := &Bullet{ID: 900, Owner: 0, Kind: "grenade", X: x, Y: y, VX: vx, R: 6, Age: .3, Life: 5}
	g.Bullets = []*Bullet{b}
	return b
}
func TestImpactGrenadeSweptAndSingleBlast(t *testing.T) {
	g := battle(3)
	g.Tanks[0].X = 40
	g.Tanks[2].X = 250
	b := impactGrenade(g, 140, 210, 2000)
	g.updateBullets(.04)
	if !b.Dead || g.Tanks[1].Alive || g.Tanks[2].Alive || blastCount(g) != 1 || b.Life <= 4.9 {
		t.Fatal("no impact blast/splash before fuse", b)
	}
	if math.Abs(b.X-(g.Tanks[1].X-g.Tanks[1].R-b.R)) > 1e-7 {
		t.Fatal("not earliest swept tank contact", b.X)
	}
	g.detonate(b)
	g.updateBullets(tickDT)
	if blastCount(g) != 1 {
		t.Fatal("duplicate impact/fuse blast")
	}
}
func TestImpactGrenadeShieldTakesExactlyOneHit(t *testing.T) {
	g := battle(2)
	g.Tanks[0].X = 40
	g.Tanks[1].Shield = 10
	b := impactGrenade(g, 164, 210, 205)
	g.updateBullets(.1)
	if !b.Dead || !g.Tanks[1].Alive || g.Tanks[1].Shield != 0 || g.Tanks[1].Invulnerable <= 0 || blastCount(g) != 1 {
		t.Fatal("contact plus blast consumed shield and killed tank")
	}
}
func TestImpactGrenadeStopsAtWallBeforeTank(t *testing.T) {
	g := battle(2)
	g.Tanks[0].X = 40
	g.Tanks[0].Y = 90
	g.World.Walls = append(g.World.Walls, Wall{X: 170, Y: 0, W: 8, H: 420})
	b := impactGrenade(g, 155, 210, 205)
	g.updateBullets(.15)
	if b.Dead || b.VX >= 0 || b.Bounces != 1 || !g.Tanks[1].Alive || blastCount(g) != 0 {
		t.Fatal("grenade penetrated wall to trigger contact")
	}
}
func TestImpactGrenadeOwnerGraceThenContact(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	p.X = 90
	g.Tanks[1].X = 400
	b := impactGrenade(g, p.X, p.Y, 0)
	b.Age = 0
	g.updateBullets(.05)
	if b.Dead || !p.Alive {
		t.Fatal("detonated inside owner's launch grace")
	}
	b.Age = .21
	g.updateBullets(tickDT)
	if !b.Dead || p.Alive || blastCount(g) != 1 {
		t.Fatal("returning/stepped-on own grenade did not explode")
	}
}
func TestImpactGrenadeStationaryContact(t *testing.T) {
	g := battle(2)
	g.Tanks[0].X = 40
	b := impactGrenade(g, g.Tanks[1].X+20, 210, 0)
	g.updateBullets(tickDT)
	if !b.Dead || g.Tanks[1].Alive {
		t.Fatal("tank can stand on live stationary grenade")
	}
}
func TestImpactGrenadeTeamAndSpawnImmunity(t *testing.T) {
	for _, kind := range []string{"ally", "invulnerable", "bot_ally", "dead"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			g.Tanks[0].X = 40
			p := g.Tanks[1]
			p.Shield = 10
			switch kind {
			case "ally":
				g.Tanks[0].Team = 1
				p.Team = 1
			case "invulnerable":
				p.Invulnerable = 10
			case "bot_ally":
				g.Tanks[0].Bot = true
				p.Bot = true
				g.Tanks[0].Team = 2
				p.Team = 2
			case "dead":
				p.Alive = false
			}
			b := impactGrenade(g, 164, 210, 205)
			g.updateBullets(.1)
			if kind == "dead" {
				if b.Dead || blastCount(g) != 0 {
					t.Fatal("wreck triggered grenade")
				}
				return
			}
			if !b.Dead || !p.Alive || p.Shield != 10 || blastCount(g) != 1 {
				t.Fatal("tank contact failed or damage bypassed immunity")
			}
		})
	}
}
func TestImpactGrenadeNoContactRetainsFiveSecondFuse(t *testing.T) {
	g := battle(2)
	b := impactGrenade(g, 250, 50, 0)
	for i := 0; i < 299; i++ {
		g.updateBullets(tickDT)
	}
	if b.Dead || blastCount(g) != 0 {
		t.Fatal("early fuse")
	}
	g.updateBullets(tickDT)
	if !b.Dead || blastCount(g) != 1 {
		t.Fatal("five second fuse lost")
	}
}
func TestImpactGrenadeOwnedRemoteTriggerStillWorks(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	b := impactGrenade(g, 250, 50, 0)
	g.weaponControl(p, true, true)
	if !b.Dead || blastCount(g) != 1 {
		t.Fatal("remote trigger lost")
	}
}
func TestMoreAggressiveMissileTurnAndAcquisition(t *testing.T) {
	g := battle(2)
	p := g.Tanks[1]
	p.X = 140
	p.Y = 290
	b := missileFor(g, 200, 210, 0)
	g.steerMissile(b, tickDT)
	if b.Target != 1 {
		t.Fatal("new wider cone not used")
	}
	turn := math.Abs(math.Atan2(b.VY, b.VX))
	if math.Abs(turn-4.8*tickDT) > 1e-8 || turn <= 2.8*tickDT {
		t.Fatal("turn rate not upgraded", turn)
	}
	if math.Abs(math.Hypot(b.VX, b.VY)-235) > 1e-8 {
		t.Fatal("speed should be unchanged")
	}
}
func TestMoreAggressiveMissileRangeAndReacquisition(t *testing.T) {
	g := battle(2)
	g.World.Walls = nil
	p := g.Tanks[1]
	p.X = 870
	p.Y = 210
	b := missileFor(g, 100, 210, 0)
	g.steerMissile(b, tickDT)
	if b.Target != 1 {
		t.Fatal("10-cell target acquisition not enabled")
	}
	b.Target = 1
	p.Invulnerable = 2
	g.steerMissile(b, tickDT)
	if b.SeekDelay != .06 {
		t.Fatal("lost-lock delay not upgraded")
	}
	p.Invulnerable = 0
	g.steerMissile(b, .03)
	if b.Target != -1 {
		t.Fatal("cooldown ignored")
	}
	g.steerMissile(b, .031)
	if b.Target != 1 {
		t.Fatal("failed to reacquire after shortened coast")
	}
}
func TestLocalRenameDuringAllPhasesPreservesGameplay(t *testing.T) {
	for _, phase := range []string{"lobby", "countdown", "playing", "roundOver", "matchOver"} {
		t.Run(phase, func(t *testing.T) {
			h, cs, r := makeRoom(t, 2)
			p := addSeat(t, h, cs[0], "local", "", 1)
			r.Game.startMatch(r.Players)
			r.Game.Phase = phase
			p.Ready = true
			p.Input = Input{Seq: 7, Fire: true}
			r.Game.Scores[p.ID] = 3
			before := *r.Game.Tanks[p.ID]
			input := p.Input
			member := p.Member
			for _, c := range cs {
				drain(c)
			}
			action(t, h, cs[0], map[string]any{"type": "rename_local", "target": p.ID, "member": p.Member, "name": "  Snow   Fox  "})
			if p.Name != "Snow Fox" || !p.Ready || p.Input != input || p.Member != member || r.Game.Scores[p.ID] != 3 || r.Game.Phase != phase {
				t.Fatal("rename changed seat/round state")
			}
			after := *r.Game.Tanks[p.ID]
			if after.Name != "Snow Fox" {
				t.Fatal("tank name not updated")
			}
			after.Name = before.Name
			a, _ := json.Marshal(before)
			b, _ := json.Marshal(after)
			if string(a) != string(b) {
				t.Fatal("rename changed tank physics")
			}
			for i, c := range cs {
				ack, room := false, false
				for _, m := range drain(c) {
					if m["type"] == "renamed" {
						ack = true
					}
					if m["type"] == "room" {
						room = true
					}
				}
				if !room || ack != (i == 0) {
					t.Fatal("rename ack broadcast wrong")
				}
			}
		})
	}
}
func TestLocalRenameRejectsOtherControllersAndSeatKinds(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := addSeat(t, h, cs[0], "local", "", 1)
	action(t, h, cs[1], map[string]any{"type": "rename_local", "target": p.ID, "member": p.Member, "name": "FORGED"})
	if p.Name == "FORGED" || !hasError(cs[1], "not_owner") {
		t.Fatal("guest renamed host local")
	}
	action(t, h, cs[0], map[string]any{"type": "rename_local", "target": 1, "member": r.Players[1].Member, "name": "FORGED"})
	if !hasError(cs[0], "not_owner") {
		t.Fatal("local rename took over remote human")
	}
	bot := addSeat(t, h, cs[0], "bot", "easy", 2)
	action(t, h, cs[0], map[string]any{"type": "rename_local", "target": bot.ID, "member": bot.Member, "name": "FORGED"})
	if !hasError(cs[0], "not_owner") {
		t.Fatal("local rename renamed bot")
	}
}
func TestLocalRenameRejectsInvalidAndStaleTargets(t *testing.T) {
	for _, bad := range []string{"missing", "negative", "large", "member", "stale", "empty", "unjoined"} {
		t.Run(bad, func(t *testing.T) {
			h, cs, _ := makeRoom(t, 1)
			p := addSeat(t, h, cs[0], "local", "", 1)
			m := map[string]any{"type": "rename_local", "target": p.ID, "member": p.Member, "name": "NEW"}
			c := cs[0]
			switch bad {
			case "missing":
				delete(m, "target")
			case "negative":
				m["target"] = -1
			case "large":
				m["target"] = 4
			case "member":
				delete(m, "member")
			case "stale":
				m["member"] = p.Member + 1
			case "empty":
				m["name"] = "<🌟>"
			case "unjoined":
				c = fakeClient()
			}
			action(t, h, c, m)
			if p.Name == "NEW" {
				t.Fatal("invalid local rename succeeded")
			}
			got := false
			for _, e := range drain(c) {
				if e["type"] == "error" && e["action"] == "rename_local" {
					got = true
				}
			}
			if !got {
				t.Fatal("no actionable rejection")
			}
		})
	}
}
func TestLocalRenameAfterHostHandoff(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := addSeat(t, h, cs[0], "local", "", 1)
	r.Host = 1
	action(t, h, cs[0], map[string]any{"type": "rename_local", "target": p.ID, "member": p.Member, "name": "OWNED"})
	if p.Name != "OWNED" || r.Host != 1 {
		t.Fatal("handoff changed ownership")
	}
	action(t, h, cs[1], map[string]any{"type": "rename_local", "target": p.ID, "member": p.Member, "name": "STOLEN"})
	if p.Name != "OWNED" || !hasError(cs[1], "not_owner") {
		t.Fatal("new host stole control of other local pilot")
	}
}
func TestLocalRenameSurvivesReconnect(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	p := addSeat(t, h, cs[0], "local", "", 1)
	action(t, h, cs[0], map[string]any{"type": "rename_local", "target": p.ID, "member": p.Member, "name": "雪 FOX"})
	owner := cs[0].player
	code, token := r.Code, owner.Token
	h.removeClient(cs[0])
	c := fakeClient()
	h.addClient(c)
	action(t, h, c, map[string]any{"type": "join", "code": code, "token": token})
	if c.room != r || r.Players[p.ID].Name != "雪 FOX" {
		t.Fatal("secondary rename lost on reconnect")
	}
}
