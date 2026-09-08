package main

import "testing"

func Test421RoomChatDeduplicatesSharedLocalSocket(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "P2", "team": 1})
	drain(cs[0])
	action(t, h, cs[0], map[string]any{"type": "chat", "channel": "room", "text": "one device"})
	if got := packetTypeCount(cs[0], "chat", "room"); got != 1 {
		t.Fatalf("shared P1/P2 socket received room chat %d times; want exactly once", got)
	}
}

func Test421MatchmakingRoomAndEnemyChatsAreDistinct(t *testing.T) {
	h := newHub(12)
	a, _ := mmRoom(t, h, 2)
	b, _ := mmRoom(t, h, 2)
	mmQueue(t, h, a, "elimination-2")
	mmQueue(t, h, b, "elimination-2")
	mmScan(h)
	if a[0].room == nil || a[0].room.Match == nil || a[0].room != b[0].room {
		t.Fatal("2v2 battle missing")
	}
	for _, c := range append(append([]*Client{}, a...), b...) {
		drain(c)
	}

	mmAction(t, h, a[0], map[string]any{"type": "chat", "channel": "room", "text": "party only"})
	if packetTypeCount(a[0], "chat", "room") != 1 || packetTypeCount(a[1], "chat", "room") != 1 {
		t.Fatal("matchmaking party chat did not reach sender party")
	}
	if packetTypeCount(b[0], "chat", "room") != 0 || packetTypeCount(b[1], "chat", "room") != 0 {
		t.Fatal("normal matchmaking chat leaked to the enemy side")
	}

	mmAction(t, h, a[0], map[string]any{"type": "chat", "channel": "opponent", "text": "enemy only"})
	if packetTypeCount(a[0], "chat", "opponent") != 1 || packetTypeCount(a[1], "chat", "opponent") != 0 {
		t.Fatal("enemy chat leaked to sender teammate or missed sender echo")
	}
	if packetTypeCount(b[0], "chat", "opponent") != 1 || packetTypeCount(b[1], "chat", "opponent") != 1 {
		t.Fatal("enemy chat did not reach opposing side")
	}
}

func Test421MatchmakingPartyHistoryIsFiltered(t *testing.T) {
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
	mmAction(t, h, a[0], map[string]any{"type": "chat", "channel": "room", "text": "alpha party"})
	mmAction(t, h, b[0], map[string]any{"type": "chat", "channel": "room", "text": "bravo party"})
	for _, c := range append(append([]*Client{}, a...), b...) {
		drain(c)
	}
	h.mu.Lock()
	h.sendChatHistory(a[0], battle)
	h.sendChatHistory(b[0], battle)
	h.mu.Unlock()
	texts := func(c *Client) []string {
		for _, m := range drain(c) {
			if m["type"] != "chat_history" || m["channel"] != "room" {
				continue
			}
			rows, _ := m["messages"].([]any)
			out := make([]string, 0, len(rows))
			for _, raw := range rows {
				if row, ok := raw.(map[string]any); ok {
					if text, ok := row["text"].(string); ok {
						out = append(out, text)
					}
				}
			}
			return out
		}
		return nil
	}
	at, bt := texts(a[0]), texts(b[0])
	if len(at) != 1 || at[0] != "alpha party" || len(bt) != 1 || bt[0] != "bravo party" {
		t.Fatalf("party histories crossed sides: a=%v b=%v", at, bt)
	}
}
