package main

import (
	"encoding/json"
	"testing"
	"time"
)

func packetTypeCount(c *Client, typ, channel string) int {
	n := 0
	for _, m := range drain(c) {
		if m["type"] == typ && (channel == "" || m["channel"] == channel) {
			n++
		}
	}
	return n
}

func TestRoomRenameMovesMapKeyAndBroadcasts(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	old := r.Code
	for _, c := range cs {
		drain(c)
	}
	action(t, h, cs[0], map[string]any{"type": "rename_room", "code": "Friday tanks 💥"})
	if r.Code != "Friday tanks 💥" || h.rooms[old] != nil || h.rooms[r.Code] != r {
		t.Fatal("room map key was not atomically renamed")
	}
	for _, c := range cs {
		seenRename, seenRoom := false, false
		for _, m := range drain(c) {
			if m["type"] == "room_renamed" && m["old"] == old && m["room"] == r.Code {
				seenRename = true
			}
			if m["type"] == "room" && m["code"] == r.Code {
				seenRoom = true
			}
		}
		if !seenRename || !seenRoom || c.room != r {
			t.Fatal("renamed room was not propagated to every connected member")
		}
	}
}

func TestRoomRenamePermissionsCollisionAndReconnect(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[1], map[string]any{"type": "rename_room", "code": "NOPE"})
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest renamed room")
	}

	other := fakeClient()
	h.addClient(other)
	action(t, h, other, map[string]any{"type": "join", "code": "TAKEN ROOM", "name": "OTHER"})
	action(t, h, cs[0], map[string]any{"type": "rename_room", "code": "TAKEN ROOM"})
	if !hasError(cs[0], "room_exists") || r.Code == "TAKEN ROOM" {
		t.Fatal("room rename collision was accepted")
	}

	old := r.Code
	token := cs[1].player.Token
	h.removeClient(cs[1])
	action(t, h, cs[0], map[string]any{"type": "rename_room", "code": "NEW ROOM"})
	reconnect := fakeClient()
	h.addClient(reconnect)
	action(t, h, reconnect, map[string]any{"type": "join", "code": old, "token": token, "name": "GUEST"})
	if reconnect.room != r || reconnect.player == nil || reconnect.room.Code != "NEW ROOM" {
		t.Fatal("in-flight reconnect did not follow renamed room")
	}
}

func TestOpponentChatOnlyReachesSenderAndEnemySide(t *testing.T) {
	h := newHub(12)
	a, _ := mmRoom(t, h, 2)
	b, _ := mmRoom(t, h, 2)
	mmQueue(t, h, a, "elimination-2")
	mmQueue(t, h, b, "elimination-2")
	mmScan(h)
	battle := a[0].room
	if battle == nil || battle.Match == nil || battle != b[0].room {
		t.Fatal("2v2 battle missing")
	}
	for _, c := range append(append([]*Client{}, a...), b...) {
		drain(c)
	}
	mmAction(t, h, a[0], map[string]any{"type": "chat", "channel": "opponent", "text": "gg enemy"})
	if packetTypeCount(a[0], "chat", "opponent") != 1 {
		t.Fatal("sender did not receive opponent chat echo")
	}
	if packetTypeCount(a[1], "chat", "opponent") != 0 {
		t.Fatal("sender teammate received opponent-only chat")
	}
	if packetTypeCount(b[0], "chat", "opponent") != 1 || packetTypeCount(b[1], "chat", "opponent") != 1 {
		t.Fatal("enemy side did not receive opponent chat")
	}
}

func TestOpponentChatHistoryIsFilteredOnReconnect(t *testing.T) {
	h := newHub(12)
	a, _ := mmRoom(t, h, 2)
	b, _ := mmRoom(t, h, 2)
	mmQueue(t, h, a, "elimination-2")
	mmQueue(t, h, b, "elimination-2")
	mmScan(h)
	battle := a[0].room
	for _, c := range append(append([]*Client{}, a...), b...) {
		drain(c)
	}
	now := time.Now()
	h.mu.Lock()
	h.chat(a[0], clientMessage{Channel: "opponent", Text: "to enemy"}, now)
	h.chat(a[1], clientMessage{Channel: "opponent", Text: "also enemy"}, now.Add(time.Second))
	h.mu.Unlock()
	for _, c := range append(append([]*Client{}, a...), b...) {
		drain(c)
	}

	// A teammate sees only their own authored opponent message in history; an
	// enemy sees both messages from the other side.
	h.mu.Lock()
	h.sendChatHistory(a[0], battle)
	h.sendChatHistory(b[0], battle)
	h.mu.Unlock()
	countMessages := func(c *Client) int {
		for _, m := range drain(c) {
			if m["type"] != "chat_history" || m["channel"] != "opponent" {
				continue
			}
			b, _ := json.Marshal(m["messages"])
			var rows []map[string]any
			_ = json.Unmarshal(b, &rows)
			return len(rows)
		}
		return -1
	}
	if got := countMessages(a[0]); got != 1 {
		t.Fatalf("sender-side history leaked teammate opponent chat: %d", got)
	}
	if got := countMessages(b[0]); got != 2 {
		t.Fatalf("enemy history missing opponent messages: %d", got)
	}
}
