package main

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func TestInfiniteVelocityIsActualDisplacementForPublicAndPrivateMovement(t *testing.T) {
	for _, private := range []bool{false, true} {
		a := newSeededInfiniteArena(37)
		if private {
			a = newRoomInfiniteArena(defaultRules(), nil)
		}
		p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		p.X, p.Y, p.Angle = 42, 42, 0
		startX, startY := p.X, p.Y
		a.drive(p, Input{Forward: true})
		if math.Abs(p.VX-128) > 1e-9 || p.VY != 0 || p.VX != (p.X-startX)/tickDT || p.VY != (p.Y-startY)/tickDT {
			t.Fatal("wire motion was not actual authoritative displacement", private, p.VX, p.VY)
		}
		p.kit.SpeedTime, p.kit.SpeedStacks = 10, 5
		a.drive(p, Input{Forward: true})
		if math.Abs(p.VX-544) > 1e-8 || p.VY != 0 {
			t.Fatal("Speed5 velocity was not published", private, p.VX, p.VY)
		}
		a.drive(p, Input{})
		if p.VX != 0 || p.VY != 0 {
			t.Fatal("neutral controls retained extrapolation velocity")
		}
	}
}

func TestInfiniteVelocityReflectsBlockedAxesInsteadOfRequestedMotion(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	var wall Wall
	for _, candidate := range a.maze.wallsNear(-500, -500, 500, 500) {
		if candidate.Axis == "v" {
			wall = candidate
			break
		}
	}
	if wall.H == 0 {
		t.Fatal("fixture needs a vertical wall")
	}
	p.X, p.Y, p.Angle = wall.X-tankRadius-.001, wall.Y+wall.H/2, math.Pi/4
	x, y := p.X, p.Y
	a.drive(p, Input{Forward: true})
	if p.X != x || p.VX != 0 || p.Y <= y || math.Abs(p.VY-(p.Y-y)/tickDT) > 1e-9 {
		t.Fatal("collision velocity still pointed into the wall", p.X-x, p.Y-y, p.VX, p.VY)
	}
}

func TestInfiniteWireVelocityResetsAcrossSpawnPauseDisconnectAndDeath(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	p.VX, p.VY = 123.4567, -8.7654
	wire := p.wireTank(0)
	if wire.VX != 123.457 || wire.VY != -8.765 {
		t.Fatal("wire precision lost derived kinematics", wire.VX, wire.VY)
	}
	if p.VX != 123.4567 || p.VY != -8.7654 {
		t.Fatal("wire conversion mutated simulation state")
	}
	for _, state := range []string{"paused", "disconnected", "dead"} {
		p.paused, p.disconnected, p.HP = state == "paused", state == "disconnected", 1
		if state == "dead" {
			p.HP = 0
		}
		wire = p.wireTank(0)
		if wire.VX != 0 || wire.VY != 0 {
			t.Fatal("stopped/dead body retained wire velocity", state)
		}
	}
	p.paused, p.disconnected = false, false
	a.spawn(p, 0, 0, 1, 3)
	if p.VX != 0 || p.VY != 0 {
		t.Fatal("respawn retained its previous life velocity")
	}
	p.VX, p.VY = 128, 20
	p.clearControls()
	if p.VX != 0 || p.VY != 0 {
		t.Fatal("disconnected/replaced controller left a moving body")
	}
	p.VX, p.VY = 128, 20
	a.eliminatePilot(p, 999, 0, "Opponent")
	if p.VX != 0 || p.VY != 0 {
		t.Fatal("eliminated tank retained physical velocity")
	}
	data, err := json.Marshal(p.wireTank(0))
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if json.Unmarshal(data, &fields) != nil || fields["vx"] != float64(0) || fields["vy"] != float64(0) {
		t.Fatal("zero velocities were omitted from the additive protocol", string(data))
	}
}

func TestInfiniteCompletedArenaPublishesZeroVelocity(t *testing.T) {
	a := newSeededInfiniteArena(37)
	c := partySnapshotClient()
	p := a.join(c, "Pilot", time.Unix(0, 0))
	p.VX, p.VY = 128, 32
	a.result = &infiniteResult{Name: "Pilot"}
	a.broadcast()
	snapshot := readPartySnapshot(t, c)
	if len(snapshot.Tanks) != 1 || snapshot.Tanks[0].VX != 0 || snapshot.Tanks[0].VY != 0 {
		t.Fatal("completed arena extrapolated frozen tanks")
	}
}
