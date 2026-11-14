package main

import (
	"encoding/json"
	"math"
	"strings"
	"testing"
	"time"
)

func noticeBoss(a *infiniteArena, number int, x, y float64) *infinitePilot {
	a.publicBotLives = 63
	bot := a.addPilot("Bot", true, 0, 0, 1, 3)
	bot.ambientNumber = number
	bot.X, bot.Y = x, y
	bot.publicBotName()
	a.recordGodlikeSpawn(bot)
	return bot
}

func TestGodlikeSpawnNoticesUseBirthLocationTTLAndBothLocalSeats(t *testing.T) {
	now := time.Unix(100, 0)
	a := newSeededInfiniteArena(37)
	primary, local := a.joinSeats(partySnapshotClient(), infiniteSeat{name: "Pilot"}, &infiniteSeat{name: "Wing"}, 0, now)
	primary.X, primary.Y, local.X, local.Y = 0, 0, 10000, 0
	bot := noticeBoss(a, 1, local.X+godlikeSpawnNoticeRange, local.Y)
	if len(a.godlikeSpawns) != 1 || a.godlikeSpawns[0].Name != "Bot 1 - Godlike" {
		t.Fatal("true boss birth lacked its original raw name")
	}
	event := a.godlikeSpawns[0]
	if !primary.nearGodlikeSpawn(event, now.Add(7*time.Second)) {
		t.Fatal("P2-only proximity did not warn its controller")
	}
	local.X -= .001
	if primary.nearGodlikeSpawn(event, now) {
		t.Fatal("notice escaped the exact 12-cell radius")
	}
	local.X += .001
	if primary.nearGodlikeSpawn(event, now.Add(8*time.Second)) {
		t.Fatal("notice outlived eight real seconds")
	}
	if primary.nearGodlikeSpawn(event, now.Add(-time.Nanosecond)) {
		t.Fatal("future birth notice appeared early")
	}
	bot.X, bot.Y = 0, 0
	if a.godlikeSpawns[0].x != event.x || a.godlikeSpawns[0].y != event.y || !a.godlikeSpawns[0].at.Equal(now) {
		t.Fatal("moving the body rewrote its birth coordinates/time")
	}
	data, _ := json.Marshal(event)
	if strings.Contains(string(data), `"x"`) || strings.Contains(string(data), `"at"`) || strings.Contains(string(data), `"y"`) || !strings.Contains(string(data), `"spawnSerial"`) {
		t.Fatal("spawn event exposed private state or lost life identity", string(data))
	}
}

func TestGodlikeSpawnNoticeMembershipSeparatesOtherwiseSharedSnapshots(t *testing.T) {
	now := time.Unix(100, 0)
	a := newSeededInfiniteArena(37)
	nearClient, farClient := partySnapshotClient(), partySnapshotClient()
	near, far := a.join(nearClient, "Near", now), a.join(farClient, "Far", now)
	near.X, near.Y, far.X, far.Y = 0, 0, -cellSize, 0
	bot := noticeBoss(a, 1, godlikeSpawnNoticeRange, 0)
	a.broadcast()
	nearState, farState := readPartySnapshot(t, nearClient), readPartySnapshot(t, farClient)
	if len(nearState.Tanks) != len(farState.Tanks) || len(nearState.GodlikeSpawns) != 1 || len(farState.GodlikeSpawns) != 0 {
		t.Fatal("cached view leaked or dropped a nearby spawn notice", len(nearState.GodlikeSpawns), len(farState.GodlikeSpawns))
	}
	if nearState.GodlikeSpawns[0].ID != bot.ID || nearState.GodlikeSpawns[0].Spawn != bot.Spawn {
		t.Fatal("snapshot did not identify the actual boss life")
	}
	a.clock = now.Add(8 * time.Second)
	a.broadcast()
	if len(readPartySnapshot(t, nearClient).GodlikeSpawns) != 0 || len(readPartySnapshot(t, farClient).GodlikeSpawns) != 0 || len(a.godlikeSpawns) != 0 {
		t.Fatal("expired birth persisted in encoded snapshots")
	}
}

func TestGodlikeSpawnNoticesOnlyTrackTruePublicBossLives(t *testing.T) {
	now := time.Unix(100, 0)
	a := newSeededInfiniteArena(37)
	human := a.join(partySnapshotClient(), "Pilot", now)
	bot := noticeBoss(a, 1, 0, 0)
	a.recordGodlikeSpawn(bot)
	if len(a.godlikeSpawns) != 1 {
		t.Fatal("same true life was recorded more than once")
	}
	first := a.godlikeSpawns[0]
	human.X, human.Y = 10000, 10000
	a.spawn(bot, human.X, human.Y, 3, 6)
	if len(a.godlikeSpawns) != 1 || a.godlikeSpawns[0].Spawn != first.Spawn || human.nearGodlikeSpawn(first, now) {
		t.Fatal("offscreen relocation created a new near-birth warning")
	}
	// Reactivate a living pooled identity near the pilot without starting a life.
	for i, p := range a.pilots {
		if p == bot {
			a.pilots = append(a.pilots[:i], a.pilots[i+1:]...)
			break
		}
	}
	a.inactiveBots = append(a.inactiveBots, bot)
	a.nextBot = a.tick
	a.populate()
	if len(a.godlikeSpawns) != 1 || a.godlikeSpawns[0].Spawn != first.Spawn {
		t.Fatal("pool activation created a new spawn event")
	}
	bot.HP, bot.respawn = 0, a.tick+1
	a.publicBotLives = 127
	a.nextBot = math.MaxUint64
	a.step(now.Add(time.Second))
	if bot.HP == 0 || len(a.godlikeSpawns) != 2 || a.godlikeSpawns[1].Spawn != bot.Spawn || a.godlikeSpawns[1].at != now.Add(time.Second) {
		t.Fatal("true Godlike respawn did not create a new bounded life event")
	}
	a.connected = 0
	a.trimRoamingBots()
	if len(a.godlikeSpawns) != 0 {
		t.Fatal("tier downgrade retained stale Godlike warnings")
	}
	private := newRoomInfiniteArena(defaultRules(), nil)
	private.clock = now
	private.connected = 1
	p := private.addPilot("Custom", true, 0, 0, 1, 3)
	p.botLevel = infiniteBotLevel("godlike")
	p.ambientNumber = 1
	private.recordGodlikeSpawn(p)
	if len(private.godlikeSpawns) != 0 {
		t.Fatal("private/custom boss emitted a public spawn warning")
	}
	private.recordGodlikeSpawn(human)
	if len(private.godlikeSpawns) != 0 {
		t.Fatal("human emitted a boss warning")
	}
}

func TestGodlikeSpawnNoticeHistoryIsBoundedAndLifeDeduplicated(t *testing.T) {
	a := newSeededInfiniteArena(37)
	a.clock = time.Unix(100, 0)
	a.connected = 1
	bot := noticeBoss(a, 1, 0, 0)
	for range 40 {
		bot.Spawn++
		a.clock = a.clock.Add(time.Millisecond)
		a.recordGodlikeSpawn(bot)
		a.recordGodlikeSpawn(bot)
	}
	if len(a.godlikeSpawns) != infiniteGodlikeNoticeLimit || a.godlikeSpawns[len(a.godlikeSpawns)-1].Spawn != bot.Spawn {
		t.Fatal("spawn history was unbounded or not deduplicated")
	}
}
