package main

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestInfinityRenameWebSocketAcknowledgesBothSeatsWithoutRejoining(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	c, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": "LEAD", "localName": "WING"}, false)
	var welcome map[string]any
	readInfinitePacket(t, reader, &welcome)
	if welcome["type"] != "welcome" || welcome["localId"] == nil {
		t.Fatalf("paired join failed: %v", welcome)
	}
	for index, name := range []string{"RENAMED", "!!!", "NEW WING"} {
		seat := 0
		if index == 2 {
			seat = 1
		}
		data, err := json.Marshal(infiniteMessage{Type: "rename", Seat: seat, RequestID: uint64(index + 1), Name: name})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := c.Write(maskedFrame(1, true, data)); err != nil {
			t.Fatal(err)
		}
		var reply map[string]any
		readInfinitePacket(t, reader, &reply)
		kind := "renamed"
		if index == 1 {
			kind = "rename_error"
		}
		if reply["type"] != kind || reply["seat"] != float64(seat) || reply["requestId"] != float64(index+1) {
			t.Fatalf("unexpected rename reply: %v", reply)
		}
	}
}

func TestInfinityRenamePreservesBothPublicTanks(t *testing.T) {
	s, _, _ := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	pair, c, rejection := tryInfinityReconnect(t, s, infiniteMessage{Name: "LEAD", LocalName: "WING", Local: true}, now)
	if rejection != "" || pair.local == nil {
		t.Fatalf("join failed: %q", rejection)
	}
	drain(c)
	pair.pilot.Score, pair.local.Score = 12, -3
	pair.local.HP, pair.local.paused = 0, true
	pair.pilot.kit.Power, pair.pilot.kit.PowerTime = "laser", 5
	before, secondBefore := *pair.pilot, *pair.local
	for index, name := range []string{"  雪!!  Fox  ", "NEW WING"} {
		s.renamePilot(c, infiniteMessage{Seat: index, RequestID: uint64(index + 1), Name: name}, now)
		messages := drain(c)
		if len(messages) != 1 || messages[0]["type"] != "renamed" || messages[0]["requestId"] != float64(index+1) || messages[0]["seat"] != float64(index) {
			t.Fatalf("missing correlated acknowledgement: %v", messages)
		}
	}
	if pair.pilot.Name != "雪 Fox" || pair.local.Name != "NEW WING" {
		t.Fatal("names were not cleaned or applied to the chosen seats")
	}
	before.Name, secondBefore.Name = pair.pilot.Name, pair.local.Name
	if *pair.pilot != before || *pair.local != secondBefore {
		t.Fatal("renaming changed tank identity, score, equipment, pause or respawn state")
	}
	c.updates = make(chan snapshotFrame, 1)
	pair.arena.broadcast()
	snapshot := readPartySnapshot(t, c)
	for _, pilot := range []*infinitePilot{pair.pilot, pair.local} {
		found := false
		for _, tank := range snapshot.Tanks {
			found = found || tank.ID == pilot.ID && tank.Name == pilot.Name
		}
		if !found {
			t.Fatalf("snapshot did not publish %q", pilot.Name)
		}
	}
}

func TestInfinityRenameUpdatesRoomMetadataAndSurvivesReconnect(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	join := infiniteMessage{Code: room.Code, Token: clients[0].player.Token}
	pair, c, rejection := tryInfinityReconnect(t, s, join, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	drain(c)
	pair.pilot.Score, pair.local.Score = 7, 3
	s.renamePilot(c, infiniteMessage{Seat: 0, RequestID: 1, Name: "NEW LEAD"}, now)
	s.renamePilot(c, infiniteMessage{Seat: 1, RequestID: 2, Name: "NEW WING"}, now)
	if pair.seat.Name != "NEW LEAD" || pair.localSeat.Name != "NEW WING" || pair.pilot.Name != pair.seat.Name || pair.local.Name != pair.localSeat.Name {
		t.Fatal("room and Infinity callsigns diverged")
	}
	roomBroadcast := false
	for _, packet := range drain(clients[0]) {
		roomBroadcast = roomBroadcast || packet["type"] == "room"
	}
	if !roomBroadcast {
		t.Fatal("renaming did not broadcast the room metadata")
	}
	s.disconnect(c, now)
	join.Resume, join.Generation = true, room.infinityGeneration
	resumed, _, rejection := tryInfinityReconnect(t, s, join, now.Add(time.Second))
	if rejection != "" || resumed.pilot != pair.pilot || resumed.local != pair.local || resumed.pilot.Name != "NEW LEAD" || resumed.local.Name != "NEW WING" || resumed.pilot.Score != 7 || resumed.local.Score != 3 {
		t.Fatalf("rename broke reconnect continuity: %q", rejection)
	}
}

func TestInfinityRenameRejectsInvalidAndRevokedSeats(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 2, true)
	now := time.Now()
	pair, c, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: clients[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	drain(c)
	for _, msg := range []infiniteMessage{{Seat: 2, RequestID: 1, Name: "FORGED"}, {Seat: -1, RequestID: 2, Name: "FORGED"}, {RequestID: 3, Name: "!!!"}, {Name: "FORGED"}, {RequestID: 1 << 53, Name: "FORGED"}} {
		before, localBefore := pair.pilot.Name, pair.local.Name
		s.renamePilot(c, msg, now)
		packets := drain(c)
		if len(packets) != 1 || packets[0]["type"] != "rename_error" || packets[0]["requestId"] != float64(msg.RequestID) || pair.pilot.Name != before || pair.local.Name != localBefore {
			t.Fatalf("invalid rename changed identity or lacked an error: %v", packets)
		}
	}
	before, localBefore := pair.pilot.Name, pair.local.Name
	action(t, s.hub, clients[0], kickRequest(pair.localSeat))
	s.renamePilot(c, infiniteMessage{Seat: 1, RequestID: 4, Name: "FORGED"}, now)
	if packets := drain(c); len(packets) != 1 || packets[0]["type"] != "rename_error" || pair.local.Name != localBefore || pair.pilot.Name != before {
		t.Fatalf("revoked co-pilot was renamed: %v", packets)
	}
	room.infinityGeneration++
	s.renamePilot(c, infiniteMessage{RequestID: 5, Name: "FORGED"}, now)
	if pair.pilot.Name != before {
		t.Fatal("an old room generation renamed a tank")
	}
}

func TestInfinityRenameRejectsReplacedTransportAndTruncatesByRune(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	join := infiniteMessage{Code: room.Code, Token: clients[0].player.Token}
	pair, original, _ := tryInfinityReconnect(t, s, join, now)
	join.Resume = true
	_, current, rejection := tryInfinityReconnect(t, s, join, now.Add(infiniteResumeIdle))
	if rejection != "" {
		t.Fatal(rejection)
	}
	s.renamePilot(original, infiniteMessage{RequestID: 1, Name: "FORGED"}, now)
	if pair.pilot.Name == "FORGED" {
		t.Fatal("replaced transport changed the current pilot")
	}
	drain(current)
	s.renamePilot(current, infiniteMessage{RequestID: 2, Name: strings.Repeat("雪", 20)}, now)
	if pair.pilot.Name != strings.Repeat("雪", 16) || pair.seat.Name != pair.pilot.Name {
		t.Fatal("Unicode callsign truncation broke room/arena parity")
	}
}
