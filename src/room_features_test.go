package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func TestRenameBroadcastsWithoutChangingIdentity(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	token := p.Token
	p.Ready = true
	r.Game.Scores[1] = 3
	for _, c := range cs {
		drain(c)
	}
	action(t, h, cs[1], map[string]any{"type": "rename", "name": "  Snow   Fox  "})
	if p.Name != "Snow Fox" || p.Token != token || p.ID != 1 || !p.Ready || r.Game.Scores[1] != 3 || r.Host != 0 || cs[1].room != r {
		t.Fatal("rename modified identity, readiness, host, score or room")
	}
	for i, c := range cs {
		found, ack := false, false
		for _, m := range drain(c) {
			if m["type"] == "room" {
				for _, v := range m["players"].([]any) {
					p := v.(map[string]any)
					if p["id"] == float64(1) && p["name"] == "Snow Fox" {
						found = true
					}
				}
			}
			if m["type"] == "renamed" {
				ack = true
				if m["id"] != float64(1) || m["name"] != "Snow Fox" {
					t.Fatal("wrong rename ack")
				}
			}
			b, _ := json.Marshal(m)
			if strings.Contains(string(b), token) {
				t.Fatal("credential leaked")
			}
		}
		if !found || ack != (i == 1) {
			t.Fatal("room update not broadcast or private ack misrouted")
		}
	}
}

func TestRenameUpdatesTankInEveryMatchPhase(t *testing.T) {
	for _, phase := range []string{"countdown", "playing", "roundOver", "matchOver"} {
		t.Run(phase, func(t *testing.T) {
			h, cs, r := makeRoom(t, 2)
			r.Game.startMatch(r.Players)
			r.Game.Phase = phase
			before := *r.Game.Tanks[1]
			g, round, clock := r.Game.Generation, r.Game.Round, r.Game.Clock
			action(t, h, cs[1], map[string]any{"type": "rename", "name": "NEW NAME"})
			after := *r.Game.Tanks[1]
			after.Name = before.Name
			b, _ := json.Marshal(before)
			a, _ := json.Marshal(after)
			if string(a) != string(b) || r.Game.Tanks[1].Name != "NEW NAME" || r.Game.Phase != phase || r.Game.Generation != g || r.Game.Round != round || r.Game.Clock != clock {
				t.Fatal("rename changed simulation state or lost tank name")
			}
		})
	}
}

func TestRenameCannotChooseAnotherPlayer(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[1], map[string]any{"type": "rename", "name": "GUEST NEW", "id": 0, "player": 0, "token": cs[0].player.Token})
	if r.Players[0].Name != "HOST" || r.Players[1].Name != "GUEST NEW" {
		t.Fatal("client-selected identity trusted")
	}
}

func TestRenameRequiresCurrentRoomMembership(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	unknown := fakeClient()
	action(t, h, unknown, map[string]any{"type": "rename", "name": "INTRUDER"})
	if !hasError(unknown, "not_joined") {
		t.Fatal("rename outside room accepted")
	}
	old := cs[1]
	h.removeClient(old)
	action(t, h, old, map[string]any{"type": "rename", "name": "DISCONNECTED"})
	if !hasError(old, "not_joined") || r.Players[1].Name != "GUEST" {
		t.Fatal("detached socket renamed pilot")
	}
	action(t, h, cs[0], map[string]any{"type": "leave"})
	action(t, h, cs[0], map[string]any{"type": "rename", "name": "LEFT"})
	if !hasError(cs[0], "not_joined") {
		t.Fatal("rename after leaving accepted")
	}
}

func TestRenameRejectsEmptyOrInvalidNames(t *testing.T) {
	for _, name := range []string{"", "   \t\n", "<>😈", "\u202e"} {
		t.Run(name, func(t *testing.T) {
			h, cs, _ := makeRoom(t, 1)
			action(t, h, cs[0], map[string]any{"type": "rename", "name": name})
			if !hasError(cs[0], "bad_name") || cs[0].player.Name != "HOST" {
				t.Fatal("invalid name accepted or old name discarded")
			}
		})
	}
}

func TestRenameUsesBoundedUnicodeCallsigns(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	action(t, h, cs[0], map[string]any{"type": "rename", "name": strings.Repeat("Å", 30) + "<script>"})
	name := cs[0].player.Name
	if utf8.RuneCountInString(name) != 16 || name != strings.Repeat("Å", 16) {
		t.Fatalf("unexpected sanitized name %q", name)
	}
	action(t, h, cs[0], map[string]any{"type": "rename", "name": "雪-FOX_42"})
	if cs[0].player.Name != "雪-FOX_42" {
		t.Fatal("supported Unicode name rejected")
	}
}

func TestRenameCanBeRepeatedAndSurvivesReconnect(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	c := cs[1]
	p := c.player
	action(t, h, c, map[string]any{"type": "rename", "name": "FIRST"})
	action(t, h, c, map[string]any{"type": "rename", "name": "SECOND"})
	action(t, h, c, map[string]any{"type": "rename", "name": "SECOND"})
	h.removeClient(c)
	resumed := fakeClient()
	action(t, h, resumed, map[string]any{"type": "join", "code": r.Code, "token": p.Token, "name": "OLD NAME"})
	if resumed.player != p || p.Name != "SECOND" {
		t.Fatal("rename lost on resume")
	}
	r.Game.startMatch(r.Players)
	if r.Game.Tanks[p.ID].Name != "SECOND" {
		t.Fatal("next match lost name")
	}
}

func TestRenameKeepsSmoothingAcknowledgementsAndInput(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	p := cs[1].player
	p.Input = Input{Seq: 123, Forward: true, Right: true}
	p.InputAt = time.Now()
	tank := r.Game.Tanks[1]
	tank.Ack = 123
	tank.AckSteps = 7
	before, at := p.Input, p.InputAt
	action(t, h, cs[1], map[string]any{"type": "rename", "name": "SMOOTH"})
	if p.Input != before || p.InputAt != at || tank.Ack != 123 || tank.AckSteps != 7 {
		t.Fatal("rename disturbed input chronology")
	}
}

func TestRenameDoesNotLeakToOtherRooms(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	other := fakeClient()
	action(t, h, other, map[string]any{"type": "create", "name": "OTHER"})
	drain(other)
	action(t, h, cs[0], map[string]any{"type": "rename", "name": "PRIVATE"})
	if len(drain(other)) != 0 {
		t.Fatal("rename broadcast to another room")
	}
}

func TestRenameUsesExistingActionRateLimit(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	c := cs[0]
	c.msgWindow = time.Now()
	c.actionCount = 8
	if h.handle(c, []byte(`{"type":"rename","name":"SPAM"}`), time.Now()) == nil {
		t.Fatal("rename bypasses action rate limit")
	}
	if c.player.Name != "HOST" {
		t.Fatal("rate-limited mutation applied")
	}
}
