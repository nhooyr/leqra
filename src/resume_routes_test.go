package main

import (
	"crypto/sha256"
	"fmt"
	"testing"
	"time"
)

func TestRoomRenameBoundsResumeRoutesAndKeepsRecentReconnect(t *testing.T) {
	h, clients, r := makeRoom(t, maxTanks)
	for i := 0; i < maxSpectators; i++ {
		c := fakeClient()
		h.addClient(c)
		action(t, h, c, map[string]any{"type": "join", "code": r.Code, "name": "VIEWER", "spectating": true})
		clients = append(clients, c)
	}
	guest := clients[len(clients)-1]
	player, token := guest.player, guest.player.Token
	h.removeClient(guest)
	now := time.Now()
	previousCode := ""
	// Eight accepted renames per second can exceed the route budget well
	// before any alias reaches the twenty-second reconnect expiry.
	for i := 0; i < maxResumeRoutes/(maxTanks+maxSpectators)+2; i++ {
		previousCode = r.Code
		now = now.Add(time.Second / 8)
		h.renameRoom(clients[0], clientMessage{Code: fmt.Sprintf("Route room %d", i)}, now)
		for _, c := range clients {
			drain(c)
		}
	}
	if len(h.resumeRoutes) > maxResumeRoutes {
		t.Fatalf("renames retained %d resume routes, limit %d", len(h.resumeRoutes), maxResumeRoutes)
	}
	reconnect := fakeClient()
	h.join(reconnect, false, previousCode, "VIEWER", token, now)
	if reconnect.room != r || reconnect.player != player {
		t.Fatal("recent pre-rename credentials did not reconnect to the same member")
	}
}

func TestResumeRouteCapacityPreservesValidRecentCredentials(t *testing.T) {
	now := time.Now()
	token := "resume-token"
	key := func(i int) resumeRouteKey {
		return resumeRouteKey{fmt.Sprintf("Previous room %d", i), sha256.Sum256([]byte(token))}
	}
	setup := func() (*Hub, *Room) {
		h := newHub(1)
		room := &Room{Code: "Current room"}
		h.rooms[room.Code] = room
		h.resumeRoutes = make(map[resumeRouteKey]resumeRoute)
		for i := 0; i < maxResumeRoutes; i++ {
			h.resumeRoutes[key(i)] = resumeRoute{room, now.Add(10*time.Second + time.Duration(i))}
		}
		return h, room
	}
	t.Run("reclaim expired and closed before eviction", func(t *testing.T) {
		h, room := setup()
		h.resumeRoutes[key(0)] = resumeRoute{room, now}
		h.resumeRoutes[key(1)] = resumeRoute{&Room{Code: "Closed room"}, now.Add(time.Minute)}
		h.rememberResumeRoute("Newest room", token, room, now)
		if len(h.resumeRoutes) != maxResumeRoutes-1 {
			t.Fatalf("stale routes were not reclaimed: %d", len(h.resumeRoutes))
		}
		for _, i := range []int{0, 1} {
			if _, exists := h.resumeRoutes[key(i)]; exists {
				t.Fatalf("stale route %d retained", i)
			}
		}
		if _, exists := h.resumeRoutes[key(2)]; !exists {
			t.Fatal("valid route evicted while stale capacity was available")
		}
	})
	t.Run("refresh without eviction and replace earliest expiry", func(t *testing.T) {
		h, room := setup()
		h.rememberResumeRoute(key(1).Code, token, room, now)
		if len(h.resumeRoutes) != maxResumeRoutes {
			t.Fatal("refresh evicted an unrelated reconnect route")
		}
		if !h.resumeRoutes[key(1)].Until.Equal(now.Add(reconnectGrace)) {
			t.Fatal("existing reconnect route did not refresh")
		}
		h.rememberResumeRoute("Newest room", token, room, now)
		if len(h.resumeRoutes) != maxResumeRoutes {
			t.Fatal("new reconnect route exceeded the capacity")
		}
		if _, exists := h.resumeRoutes[key(0)]; exists {
			t.Fatal("earliest-expiring route was not evicted")
		}
		if _, exists := h.resumeRoutes[key(1)]; !exists {
			t.Fatal("recently refreshed route was evicted")
		}
	})
}
