package main

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func roomFixture443() (*Hub, *Room) {
	h := newHub(4)
	r := &Room{Code: "ROOM <&> 雪", Host: 0, Game: newGame(443), Spectators: map[int]*Player{}}
	for id, kind := range []string{"human", "local", "bot", "human"} {
		p := &Player{ID: id, Member: uint64(100 + id), Name: "PILOT <&> 雪", Token: "PRIVATE-TOKEN-443", Kind: kind, Owner: 0, Difficulty: "godlike", Ready: true}
		if id == 0 {
			p.Client = fakeClient()
		}
		r.Players[id] = p
		r.Game.Scores[id] = id + 1
	}
	r.Spectators[40] = &Player{ID: 40, Member: 140, Kind: "local", Owner: 0, Name: "LOCAL VIEWER", Spectating: true, Ready: true}
	r.Spectators[9] = &Player{ID: 9, Member: 109, Name: "REMOTE VIEWER", Spectating: true, Client: fakeClient()}
	return h, r
}
func assertRoomWire443(t *testing.T, h *Hub, r *Room) {
	t.Helper()
	want, err := json.Marshal(h.roomMessage(r))
	if err != nil {
		t.Fatal(err)
	}
	got, err := json.Marshal(h.roomWire(r))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("room wire differs\ngot:  %s\nwant: %s", got, want)
	}
	if bytes.Contains(got, []byte("PRIVATE-TOKEN-443")) {
		t.Fatal("public wire exposed a private token")
	}
}
func TestRoomWire443AllModesPhasesAndOptionalColors(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth", "survival"} {
		for _, format := range []string{"ffa", "teams"} {
			for _, phase := range []string{"lobby", "countdown", "playing", "roundOver", "matchOver"} {
				h, r := roomFixture443()
				r.Game.Rules.Mode = mode
				r.Game.Rules.TeamMode = format
				r.Game.Phase = phase
				for id, p := range r.Players {
					if p != nil {
						p.Team = id%2 + 1
						color := id % 3
						p.ColorIndex = &color
					}
				}
				assertRoomWire443(t, h, r)
				r.Players[0].Client = nil
				assertRoomWire443(t, h, r)
			}
		}
	}
}
func TestRoomWire443QueueTravelAndFalseRematchPresence(t *testing.T) {
	h, r := roomFixture443()
	now := time.Unix(1_800_000_000, 0)
	r.Queue = &QueueTicket{ID: 55, Room: r, Leader: r.Players[0], Pilots: []*Player{r.Players[0], r.Players[1]}, Created: now, Definition: QueueDefinition{Key: "elimination-2", Name: "Duo", Players: 2}, Accepted: map[*Player]bool{r.Players[0]: true}}
	assertRoomWire443(t, h, r)
	r.Queue.Enqueued = now.Add(time.Second)
	assertRoomWire443(t, h, r)
	r.Queue = nil
	r.Players[0].Away = &MatchTravel{Battle: &Room{Code: "BATTLE"}}
	assertRoomWire443(t, h, r)
	r.Players[0].Away = nil
	r.Players[0].Return = &MatchTravel{}
	r.Match = &QueueMatch{Definition: QueueDefinition{Key: "elimination-2", Name: "Duo"}, Rematch: map[uint64]bool{r.Players[0].Member: true}}
	for _, phase := range []string{"playing", "matchOver"} {
		r.Game.Phase = phase
		assertRoomWire443(t, h, r)
	}
	wire := h.roomWire(r)
	if wire.Players[1].Rematch == nil || *wire.Players[1].Rematch {
		t.Fatal("explicit false rematch vote was omitted or changed")
	}
	r.Match.Rematch = nil
	assertRoomWire443(t, h, r)
	if h.roomWire(r).Players[0].Rematch != nil {
		t.Fatal("nil vote table invented a rematch field")
	}
}
func TestRoomWire443PreparedRecordsCopyMutableMemberFields(t *testing.T) {
	h, r := roomFixture443()
	color := 0
	r.Players[0].ColorIndex = &color
	r.Match = &QueueMatch{Rematch: map[uint64]bool{r.Players[0].Member: true}}
	r.Game.Phase = "matchOver"
	want, _ := json.Marshal(h.roomMessage(r))
	wire := h.roomWire(r)
	color = 4
	r.Players[0].Name = "RENAMED"
	r.Match.Rematch[r.Players[0].Member] = false
	got, _ := json.Marshal(wire)
	if !bytes.Equal(got, want) {
		t.Fatal("later member edits mutated a prepared wire record")
	}
	assertRoomWire443(t, h, r)
}
func TestRoomWire443EmptyCollectionsRemainArrays(t *testing.T) {
	h := newHub(1)
	r := &Room{Code: "EMPTY", Host: -1, Game: newGame(443)}
	assertRoomWire443(t, h, r)
	raw, _ := json.Marshal(h.roomWire(r))
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"players", "spectators"} {
		if string(decoded[key]) != "[]" {
			t.Fatalf("%s encoded as %s", key, decoded[key])
		}
	}
}
