package main

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"
)

func TestPublicInfinitySelectedPaintSurvivesReentry(t *testing.T) {
	for color := range len(tankColors) {
		t.Run(fmt.Sprint(color), func(t *testing.T) {
			localColor := (color + 3) % len(tankColors)
			var join infiniteMessage
			packet := fmt.Sprintf(`{"name":"PRIMARY","localName":"SECONDARY","colorIndex":%d,"localColorIndex":%d}`, color, localColor)
			if err := json.Unmarshal([]byte(packet), &join); err != nil {
				t.Fatal(err)
			}
			s := newInfiniteServer(newHub(2))
			now := time.Now()
			for range 2 {
				pair, c, rejection := tryInfinityReconnect(t, s, join, now)
				if rejection != "" || pair.local == nil || pair.pilot.ColorIndex != color || pair.local.ColorIndex != localColor {
					t.Fatalf("public join lost selected paint %d/%d: %+v, %q", color, localColor, pair, rejection)
				}
				drain(c)
				pair.arena.broadcast()
				var snapshot infiniteSnapshot
				if err := json.Unmarshal(<-c.send, &snapshot); err != nil {
					t.Fatal(err)
				}
				if len(snapshot.Tanks) != 2 || snapshot.Tanks[0].ColorIndex != color || snapshot.Tanks[1].ColorIndex != localColor ||
					len(snapshot.Leaders) != 2 || snapshot.Leaders[0].ColorIndex != color || snapshot.Leaders[1].ColorIndex != localColor {
					t.Fatal("tank or leaderboard paint differs from the selected public colors")
				}
				s.remove(c)
			}
		})
	}
}

func TestPublicInfinityUnselectedOrInvalidPaintKeepsAutomaticColors(t *testing.T) {
	for _, value := range []string{"null", "-1", "-2", "8", "999"} {
		t.Run(value, func(t *testing.T) {
			var join infiniteMessage
			packet := fmt.Sprintf(`{"localName":"SECONDARY","colorIndex":%s,"localColorIndex":%s}`, value, value)
			if err := json.Unmarshal([]byte(packet), &join); err != nil {
				t.Fatal(err)
			}
			s := newInfiniteServer(newHub(2))
			pair, _, rejection := tryInfinityReconnect(t, s, join, time.Now())
			if rejection != "" || pair.local == nil || pair.pilot.ColorIndex != 0 || pair.local.ColorIndex != 1 {
				t.Fatalf("invalid or automatic paint changed legacy public colors: %q", rejection)
			}
		})
	}
}

func TestPrivateInfinityIgnoresCallerPaintOnJoinAndResume(t *testing.T) {
	h, clients, room := makeRoom(t, 1)
	host := clients[0]
	rules := room.Game.settings()
	rules.Infinity, rules.TeamMode = true, "ffa"
	action(t, h, host, map[string]any{"type": "rules", "rules": rules})
	action(t, h, host, map[string]any{"type": "paint", "colorIndex": 5})
	action(t, h, host, map[string]any{"type": "add", "kind": "local", "name": "WINGMATE"})
	local := room.Players[1]
	if local == nil {
		t.Fatal("local player was not added")
	}
	action(t, h, host, map[string]any{"type": "paint", "target": local.ID, "member": local.Member, "colorIndex": 2})
	action(t, h, host, map[string]any{"type": "start"})
	s := newInfiniteServer(h)
	var join infiniteMessage
	packet := fmt.Sprintf(`{"code":%q,"token":%q,"name":"FORGED","localName":"FORGED","colorIndex":0,"localColorIndex":7}`, room.Code, host.player.Token)
	if err := json.Unmarshal([]byte(packet), &join); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	pair, c, rejection := tryInfinityReconnect(t, s, join, now)
	if rejection != "" || pair.local == nil || pair.pilot.ColorIndex != 5 || pair.local.ColorIndex != 2 {
		t.Fatalf("private paint did not follow the authenticated room roster: %q", rejection)
	}
	s.disconnect(c, now)
	join.Resume, join.Generation = true, room.infinityGeneration
	resumed, _, rejection := tryInfinityReconnect(t, s, join, now.Add(time.Millisecond))
	if rejection != "" || resumed.pilot != pair.pilot || resumed.local != pair.local || resumed.pilot.ColorIndex != 5 || resumed.local.ColorIndex != 2 {
		t.Fatalf("private reconnect changed the authoritative tank paint: %q", rejection)
	}
}
