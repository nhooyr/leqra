package main

import (
	"math"
	"testing"
	"time"
)

func huntFixture(t *testing.T) (*infiniteArena, *infinitePilot, *infinitePilot, *infinitePilot) {
	t.Helper()
	a := newSeededInfiniteArena(37)
	human := a.join(fakeClient(), "Human", time.Unix(0, 0))
	boss := a.addPilot("Boss", true, human.X, human.Y, 3, 6)
	blocker := a.addPilot("Blocker", true, human.X, human.Y, 3, 6)
	boss.botLevel = infiniteBotLevel("godlike")
	for cy := -12; cy <= 12; cy++ {
		for cx := -12; cx <= 12; cx++ {
			x, y := infiniteCenter(cx, cy)
			if a.rayBlocked(x, y, cellSize*3, 0, infiniteBulletRadius) {
				continue
			}
			boss.X, boss.Y, boss.Angle = x, y, 0
			blocker.X, blocker.Y = x+cellSize, y
			human.X, human.Y = x+3*cellSize, y
			for _, p := range []*infinitePilot{boss, blocker, human} {
				p.Protected, p.kit.SpawnProtected, p.kit.Invulnerable = false, false, 0
			}
			return a, boss, blocker, human
		}
	}
	t.Fatal("fixture needs a connected straight corridor")
	return nil, nil, nil, nil
}

func TestPublicGodlikePursuesHumanAndClearsInterceptingBots(t *testing.T) {
	a, boss, blocker, human := huntFixture(t)
	input := a.botInput(boss)
	if boss.botTarget != human.ID || !input.Fire || input.AimOnly || input.StickX <= 0 {
		t.Fatal("boss stopped to duel the closer bot instead of pursuing the human", input)
	}
	a.fire(boss)
	for range 30 {
		a.advanceBullets()
	}
	if blocker.HP != 0 || boss.botTarget != human.ID || human.HP == 0 {
		t.Fatal("the intervening bot did not intercept the shot while the human remained the hunt target")
	}
}

func TestPublicGodlikeFindsHumansBeyondOrdinarySightAndExcludesDeadDisconnected(t *testing.T) {
	a, boss, blocker, human := huntFixture(t)
	human.X, human.Y = boss.X+13*cellSize, boss.Y+2*cellSize
	input := a.botInput(boss)
	if boss.botTarget != human.ID || math.Hypot(input.StickX, input.StickY) == 0 || input.AimOnly {
		t.Fatal("boss ignored a living human beyond its firing sight", input)
	}
	human.disconnected = true
	a.botInput(boss)
	if boss.botTarget != 0 {
		t.Fatal("disconnected human remained the hunt target")
	}
	human.disconnected, human.HP = false, 0
	a.botInput(boss)
	if boss.botTarget != 0 || blocker.HP == 0 {
		t.Fatal("boss began hunting bots without a living human")
	}
}

func TestPublicGodlikeRouteUsesOpenMazeConnections(t *testing.T) {
	a, boss, _, human := huntFixture(t)
	cx, cy := infiniteCell(boss.X, boss.Y)
	human.X, human.Y = infiniteCenter(cx+12, cy+7)
	next, ok := a.huntWaypoint(cx, cy, human)
	nx, ny := infiniteCenter(next[0], next[1])
	if !ok || math.Abs(float64(next[0]-cx))+math.Abs(float64(next[1]-cy)) != 1 || a.maze.blocked((boss.X+nx)/2, (boss.Y+ny)/2, tankRadius) {
		t.Fatal("hunt chose a wall or a disconnected jump", next)
	}
}

func TestPublicGodlikeFollowsItsWaypointBetweenCellCenters(t *testing.T) {
	a, boss, _, human := huntFixture(t)
	cx, cy := infiniteCell(boss.X, boss.Y)
	for dy := -8; dy <= 8; dy++ {
		for dx := -8; dx <= 8; dx++ {
			human.X, human.Y = infiniteCenter(cx+dx, cy+dy)
			if math.Hypot(human.X-boss.X, human.Y-boss.Y) < 4*cellSize || !a.rayBlocked(boss.X, boss.Y, human.X-boss.X, human.Y-boss.Y, infiniteBulletRadius) {
				continue
			}
			initialX, initialY := boss.X, boss.Y
			for range 180 {
				a.drive(boss, a.botInput(boss))
			}
			if math.Hypot(boss.X-initialX, boss.Y-initialY) < cellSize {
				t.Fatal("boss oscillated around its departure cell instead of following the route")
			}
			return
		}
	}
	t.Fatal("fixture needs a human behind a wall")
}
