package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"reflect"
	"testing"
	"time"
)

func partySnapshotClient() *Client {
	c := fakeClient()
	c.updates = make(chan snapshotFrame, 1)
	return c
}

func readPartySnapshot(t *testing.T, c *Client) infiniteSnapshot {
	t.Helper()
	frame := <-c.updates
	var snapshot infiniteSnapshot
	if err := json.Unmarshal(frame.data, &snapshot); err != nil {
		t.Fatal(err)
	}
	return snapshot
}

func TestInfinitePartySnapshotIncludesDistantReservedScoresAndGlobalRanks(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Unix(0, 0)
	c := partySnapshotClient()
	primary, local := a.joinSeats(c, infiniteSeat{name: "First", colorIndex: 0}, &infiniteSeat{name: "Second", colorIndex: 7}, 1, now)
	remote := a.join(partySnapshotClient(), "Remote", now)
	party := infiniteRoom{room: &Room{}, generation: 1}
	a.bindParty(primary, local, party, 101, 102)
	a.bindParty(remote, nil, party, 201, 0)
	primary.X, primary.Y, local.X, local.Y = 0, 0, 0, 0
	remote.X, remote.Y, remote.HP, remote.Score, remote.ColorIndex = 5000, 5000, 0, -4, 5
	remote.respawn = 60
	primary.Score, local.Score = 7, 7
	a.suspend(remote)
	for i := range 12 {
		bot := a.addPilot(fmt.Sprintf("Leader %d", i), true, 10000, 10000, 0, 0)
		bot.Score = 100 - i
	}
	a.broadcast()
	snapshot := readPartySnapshot(t, c)
	want := []infinitePartyLeader{
		{ID: primary.ID, Member: 101, Name: "First", Score: 7, ColorIndex: 0, Rank: 13},
		{ID: local.ID, Member: 102, Name: "Second", Score: 7, ColorIndex: 7, Rank: 14},
		{ID: remote.ID, Member: 201, Name: "Remote", Score: -4, ColorIndex: 5, Rank: 15},
	}
	if !reflect.DeepEqual(snapshot.Party, want) {
		t.Fatalf("party scores/ranks differ: got %+v want %+v", snapshot.Party, want)
	}
	if len(snapshot.Leaders) != 10 || len(snapshot.Tanks) != 2 {
		t.Fatalf("party summaries changed the top ten or exposed distant bodies: %+v", snapshot)
	}
	for _, leader := range snapshot.Leaders {
		if !leader.Bot {
			t.Fatal("outside-top-ten party rows displaced a global leader")
		}
	}
	data, err := json.Marshal(snapshot.Party[0])
	if err != nil || !bytes.Contains(data, []byte(`"colorIndex":0`)) || bytes.Contains(data, []byte(`"x"`)) || bytes.Contains(data, []byte(`"token"`)) {
		t.Fatalf("party summary lost palette zero or exposed private fields: %s (%v)", data, err)
	}

	a.remove(remote)
	a.broadcast()
	if got := readPartySnapshot(t, c).Party; !reflect.DeepEqual(got, want[:2]) {
		t.Fatalf("departed party member remained in the summary: %+v", got)
	}
}

func TestInfinitePartySnapshotSharingRespectsRoomAndGeneration(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Unix(0, 0)
	room := &Room{}
	firstParty, nextGeneration := infiniteRoom{room: room, generation: 1}, infiniteRoom{room: room, generation: 2}
	var clients [5]*Client
	var pilots [5]*infinitePilot
	for i := range clients {
		clients[i] = partySnapshotClient()
		clients[i].ws = &wsConn{deflate: true}
		pilots[i] = a.join(clients[i], fmt.Sprintf("Pilot %d", i), now)
		pilots[i].X, pilots[i].Y = 0, 0
	}
	a.bindParty(pilots[0], nil, firstParty, 101, 0)
	a.bindParty(pilots[1], nil, firstParty, 102, 0)
	a.bindParty(pilots[2], nil, nextGeneration, 201, 0)
	a.bindParty(pilots[3], nil, infiniteRoom{room: &Room{}, generation: 1}, 301, 0)
	a.broadcast()
	var frames [5]snapshotFrame
	for i, c := range clients {
		frames[i] = <-c.updates
	}
	if &frames[0].data[0] != &frames[1].data[0] {
		t.Fatal("equal views from the same party no longer share compressed bytes")
	}
	for i := 2; i < len(frames); i++ {
		if &frames[0].data[0] == &frames[i].data[0] {
			t.Fatal("another room, generation, or solo viewer shared party data")
		}
	}
	for i, frame := range frames {
		data, err := inflateMessage(frame.data, lenLimitForTest)
		if err != nil {
			t.Fatal(err)
		}
		var snapshot infiniteSnapshot
		if err := json.Unmarshal(data, &snapshot); err != nil {
			t.Fatal(err)
		}
		if i < 2 {
			if len(snapshot.Party) != 2 || snapshot.Party[0].Member != 101 || snapshot.Party[1].Member != 102 {
				t.Fatalf("party summary differs for peer %d: %+v", i, snapshot.Party)
			}
		} else if i < 4 {
			if len(snapshot.Party) != 1 || snapshot.Party[0].Member != uint64(i*100+1) {
				t.Fatalf("peer %d saw another party: %+v", i, snapshot.Party)
			}
		} else if len(snapshot.Party) != 0 || bytes.Contains(data, []byte(`"party"`)) {
			t.Fatalf("solo viewer received party data: %+v", snapshot.Party)
		}
	}
}
