package main

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

func callsignRoomError(t *testing.T, c *Client, action string, seat int) {
	t.Helper()
	for _, m := range drain(c) {
		if m["type"] == "error" && m["code"] == "callsign_taken" {
			if m["action"] != action {
				t.Fatal("wrong conflict action", m)
			}
			conflicts, ok := m["conflicts"].([]any)
			if !ok || len(conflicts) != 1 || conflicts[0].(map[string]any)["seat"] != float64(seat) {
				t.Fatal("wrong conflict seat", m)
			}
			return
		}
	}
	t.Fatal("missing callsign_taken")
}

func TestPrivateOnlineCallsignClaimsAreCaseInsensitiveDurableAndOwnerScoped(t *testing.T) {
	h := newHub(8)
	first := fakeClient()
	action(t, h, first, map[string]any{"type": "create", "name": "Snow Fox"})
	p := first.player
	if p == nil || p.PublicToken == "" || p.PublicToken == p.Token {
		t.Fatal("private admission did not allocate separate durable owner")
	}
	owner, roomToken := p.PublicToken, p.Token
	for _, packet := range drain(first) {
		if packet["type"] == "welcome" && packet["publicToken"] != owner {
			t.Fatal("welcome omitted private owner proof")
		}
	}
	action(t, h, first, map[string]any{"type": "rename", "name": "Polar Fox"})
	action(t, h, first, map[string]any{"type": "leave"})
	for _, name := range []string{"SNOW FOX", "polar fox"} {
		stranger := fakeClient()
		action(t, h, stranger, map[string]any{"type": "create", "name": name})
		callsignRoomError(t, stranger, "create", 0)
		if stranger.room != nil {
			t.Fatal("conflicting admission created membership")
		}
	}
	second := fakeClient()
	action(t, h, second, map[string]any{"type": "create", "name": "SNOW FOX", "publicToken": owner})
	if second.player == nil || second.player.PublicToken != owner || second.player.Token == roomToken {
		t.Fatal("owner could not reuse its callsign with a fresh room credential")
	}
	stranger := fakeClient()
	action(t, h, stranger, map[string]any{"type": "create", "name": "Unclaimed", "publicToken": roomToken})
	if stranger.room != nil || !hasError(stranger, "public_resume_invalid") {
		t.Fatal("room token impersonated durable owner")
	}
	if got := h.callsigns.availability("", []string{"Unclaimed"}); !got[0].Available {
		t.Fatal("rejected owner attempt reserved a callsign")
	}
}

func TestPrivateLocalCallsignClaimsAreAtomicAcrossAddRenameConfigureAndPreset(t *testing.T) {
	h := newHub(8)
	host, other := fakeClient(), fakeClient()
	action(t, h, host, map[string]any{"type": "create", "name": "Lead"})
	action(t, h, other, map[string]any{"type": "create", "name": "Reserved"})
	r := host.room
	action(t, h, host, map[string]any{"type": "add", "kind": "local", "name": "RESERVED"})
	callsignRoomError(t, host, "add", 1)
	if participantCount(r.Players) != 1 {
		t.Fatal("failed local add changed roster")
	}
	action(t, h, host, map[string]any{"type": "add", "kind": "local", "name": "Wing"})
	local := r.Players[1]
	if local == nil {
		t.Fatal("clear local callsign failed")
	}
	for _, kind := range []string{"rename_local", "configure"} {
		action(t, h, host, map[string]any{"type": kind, "target": local.ID, "member": local.Member, "name": "Reserved"})
		callsignRoomError(t, host, kind, 1)
		if local.Name != "Wing" {
			t.Fatal("failed local rename changed metadata")
		}
	}
	action(t, h, host, map[string]any{"type": "rename", "name": "Wing"})
	callsignRoomError(t, host, "rename", 1)
	if host.player.Name != "Lead" {
		t.Fatal("primary collided with its local pilot")
	}
	rules := r.Game.settings()
	roster := []SeatSpec{{Kind: "human", Name: "New Lead"}, {Kind: "local", Name: "Reserved"}}
	action(t, h, host, map[string]any{"type": "preset", "rules": rules, "roster": roster})
	callsignRoomError(t, host, "preset", 1)
	if r.Players[1] != local || host.player.Name != "Lead" {
		t.Fatal("conflicting preset partially replaced the lobby")
	}
	if !h.callsigns.availability("", []string{"New Lead"})[0].Available {
		t.Fatal("failed batch reserved its clear primary name")
	}
	host.msgWindow = time.Time{}
	action(t, h, host, map[string]any{"type": "rename_local", "target": local.ID, "member": local.Member, "name": "New Wing"})
	if local.Name != "New Wing" {
		t.Fatal("available local rename failed")
	}
	if h.callsigns.availability("", []string{"Wing", "New Wing"})[0].Available {
		t.Fatal("renaming released a previous local alias")
	}
}

func TestPublishCallsignBatchIsAtomicAndNeverBroadcastsOwnerBearer(t *testing.T) {
	h := newHub(8)
	taken := fakeClient()
	action(t, h, taken, map[string]any{"type": "create", "name": "Taken"})
	publisher := fakeClient()
	roster := []SeatSpec{{Kind: "human", Name: "Clear"}, {Kind: "bot", Name: "Taken", Difficulty: "normal"}, {Kind: "local", Name: "Taken"}}
	action(t, h, publisher, map[string]any{"type": "publish", "code": "Batch", "roster": roster})
	callsignRoomError(t, publisher, "publish", 1)
	if publisher.room != nil || h.rooms["Batch"] != nil || !h.callsigns.availability("", []string{"Clear"})[0].Available {
		t.Fatal("failed publish partially committed")
	}
	roster[2].Name = "Wing"
	action(t, h, publisher, map[string]any{"type": "publish", "code": "Batch", "roster": roster})
	if publisher.room == nil {
		t.Fatal("valid publish failed", drain(publisher))
	}
	owner := publisher.player.PublicToken
	for _, packet := range drain(publisher) {
		if packet["type"] != "welcome" && strings.Contains(fmt.Sprint(packet), owner) {
			t.Fatal("durable owner leaked to room metadata")
		}
	}
	setup := infiniteRoomSeat(publisher.player, publisher.room.Game.settings())
	local := infiniteRoomSeat(publisher.room.Players[2], publisher.room.Game.settings())
	if setup.publicToken != owner || local.publicToken != "" {
		t.Fatal("room Infinity did not scope bearer to primary controller")
	}
}

func TestPrivateOnlineCallsignResumeKeepsOwnerAndRejectsSpectatorRenameCollision(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	old := cs[0]
	p := old.player
	owner, token := p.PublicToken, p.Token
	h.removeClient(old)
	resumed := fakeClient()
	action(t, h, resumed, map[string]any{"type": "join", "code": r.Code, "token": token, "name": "GUEST", "spectating": true})
	callsignRoomError(t, resumed, "join", 0)
	if resumed.player != nil || p.Name != "HOST" || p.PublicToken != owner {
		t.Fatal("rejected resume changed reserved identity")
	}
	action(t, h, resumed, map[string]any{"type": "join", "code": r.Code, "token": token, "name": "Watch Fox", "spectating": true})
	if resumed.player != p || p.PublicToken != owner || p.Name != "Watch Fox" {
		t.Fatal("authenticated resume lost durable owner")
	}
}
