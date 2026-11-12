package main

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

func publicPartyFixture(t *testing.T, local bool) (*infiniteServer, []*Client, *Room) {
	t.Helper()
	h, cs, r := makeRoom(t, 2)
	if local {
		action(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "WING"})
	}
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "name": "REMOVABLE"})
	action(t, h, cs[0], map[string]any{"type": "select_public_infinity", "enabled": true})
	readyAll(t, h, cs[1:])
	return newInfiniteServer(h), cs, r
}
func launchPublicParty(t *testing.T, s *infiniteServer, c *Client, now time.Time) {
	t.Helper()
	action(t, s.hub, c, map[string]any{"type": "start_public_infinity"})
	s.step(now)
	if !c.room.infinityActive || !c.room.infinityPublic {
		t.Fatalf("public party launch failed: %v", drain(c))
	}
}
func TestPublicInfinityRoomPartyUsesPublicFFAAndKeepsRoomPaint(t *testing.T) {
	s, cs, r := publicPartyFixture(t, true)
	now := time.Now()
	r.Game.Rules.TeamColors = []int{6, 5, 4, 3}
	before := normalizedRules(r.Game.settings())
	colors := map[*Player]int{}
	for _, p := range r.Players {
		if p != nil {
			colors[p] = tankColorIndex[selectedColor(p.ID, p.Team, p.ColorIndex, before)]
		}
	}
	viewer := fakeClient()
	s.hub.addClient(viewer)
	action(t, s.hub, viewer, map[string]any{"type": "join", "code": r.Code, "name": "VIEWER", "spectating": true})
	drain(viewer)
	action(t, s.hub, cs[1], map[string]any{"type": "start_public_infinity"})
	if !hasError(cs[1], "public_infinity_unavailable") {
		t.Fatal("guest launched party")
	}
	launchPublicParty(t, s, cs[0], now)
	if !reflect.DeepEqual(before, r.Game.settings()) || s.publicPendingCount != 3 || s.privateCount != 0 {
		t.Fatal("launch mutated saved rules or reserved wrong arena capacity")
	}
	for _, p := range r.Players {
		if p != nil && p.Kind == "bot" {
			t.Fatal("configured bot survived public entry")
		}
	}
	for _, p := range drain(viewer) {
		if p["type"] == "infinity_start" {
			t.Fatal("source spectator was promoted into public play")
		}
	}
	pair, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: cs[0].player.Token}, now)
	if reject != "" || pair.local == nil || pair.arena != s.public {
		t.Fatalf("host pair not public: %s", reject)
	}
	guest, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: cs[1].player.Token}, now)
	if reject != "" || guest.arena != pair.arena {
		t.Fatalf("guest not in same public arena: %s", reject)
	}
	for _, entry := range []struct {
		tank   *infinitePilot
		member *Player
	}{{pair.pilot, pair.seat}, {pair.local, pair.localSeat}, {guest.pilot, guest.seat}} {
		if entry.tank.Team != 0 || entry.tank.ColorIndex != colors[entry.member] {
			t.Fatal("public pilot inherited private team damage rules or lost visible paint")
		}
	}
	if s.public.players != 3 || s.publicPendingCount != 0 || s.privateCount != 0 {
		t.Fatal("public party consumed private capacity or leaked pending places")
	}
}
func TestPublicInfinityRoomPartyAdmissionIsAtomicAndReservesPlaces(t *testing.T) {
	s, cs, r := publicPartyFixture(t, true)
	now := time.Now()
	var public []*Client
	for i := 0; i < infiniteCapacity-2; i++ {
		_, c, reject := tryInfinityReconnect(t, s, infiniteMessage{Name: "OUTSIDER"}, now)
		if reject != "" {
			t.Fatal(reject)
		}
		public = append(public, c)
	}
	action(t, s.hub, cs[0], map[string]any{"type": "start_public_infinity"})
	s.step(now)
	if r.infinityActive || !r.infinityPublic || s.publicPendingCount != 0 || !hasError(cs[0], "public_infinity_unavailable") {
		t.Fatal("overfull public party partially launched")
	}
	bots := 0
	for _, p := range r.Players {
		if p != nil && p.Kind == "bot" {
			bots++
		}
	}
	if bots != 1 {
		t.Fatal("failed public launch cleared source bots")
	}
	s.remove(public[0])
	launchPublicParty(t, s, cs[0], now)
	if s.public.players+s.publicPendingCount != infiniteCapacity {
		t.Fatal("launch did not reserve every party seat")
	}
	if _, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Name: "LATE OUTSIDER"}, now); reject == "" {
		t.Fatal("unrelated pilot stole reserved party place")
	}
	for _, c := range cs {
		if _, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: c.player.Token}, now); reject != "" {
			t.Fatal(reject)
		}
	}
	if s.public.players != infiniteCapacity || s.publicPendingCount != 0 {
		t.Fatal("party could not consume reserved places at public capacity")
	}
}
func TestPublicInfinityRoomPartyReconnectLeaveAndEnd(t *testing.T) {
	s, cs, r := publicPartyFixture(t, true)
	now := time.Now()
	launchPublicParty(t, s, cs[0], now)
	pair, old, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: cs[0].player.Token}, now)
	if reject != "" {
		t.Fatal(reject)
	}
	guest, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: cs[1].player.Token}, now)
	if reject != "" {
		t.Fatal(reject)
	}
	outsider, outsideSocket, reject := tryInfinityReconnect(t, s, infiniteMessage{Name: "OUTSIDE"}, now)
	if reject != "" {
		t.Fatal(reject)
	}
	pair.pilot.Score, pair.local.Score = 9, 4
	s.disconnect(old, now)
	resumed, fresh, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: pair.seat.Token, Resume: true, Generation: r.infinityGeneration}, now.Add(time.Second))
	if reject != "" || resumed.pilot != pair.pilot || resumed.local != pair.local || resumed.pilot.Score != 9 || resumed.local.Score != 4 || s.privateCount != 0 {
		t.Fatal("public party reconnect lost identity or private accounting")
	}
	action(t, s.hub, cs[0], map[string]any{"type": "spectate", "target": pair.localSeat.ID, "member": pair.localSeat.Member, "spectating": true})
	s.step(now.Add(time.Second))
	resumed, _, reject = tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: pair.seat.Token, Resume: true, Generation: r.infinityGeneration}, now.Add(2*time.Second))
	if reject != "" || resumed.local != nil || resumed.pilot.Score != 9 || s.privateCount != 0 {
		t.Fatal("public local revocation damaged primary or private capacity")
	}
	_ = fresh
	action(t, s.hub, cs[0], map[string]any{"type": "leave"})
	s.step(now.Add(2 * time.Second))
	if s.public.players != 2 || guest.pilot.client == nil {
		t.Fatal("room departure removed wrong public pilots")
	}
	action(t, s.hub, cs[1], map[string]any{"type": "lobby"})
	s.step(now.Add(3 * time.Second))
	if s.public.players != 1 || outsider.pilot.client != outsideSocket || s.privateCount != 0 || s.publicPendingCount != 0 {
		t.Fatal("ending party affected unrelated public pilot or retained capacity")
	}
}
func TestPublicInfinityRoomPartySpectatorHostAndLocalLimitation(t *testing.T) {
	for _, local := range []bool{false, true} {
		t.Run(map[bool]string{false: "spectating host", true: "spectating local controller"}[local], func(t *testing.T) {
			s, cs, r := publicPartyFixture(t, local)
			action(t, s.hub, cs[0], map[string]any{"type": "spectate", "spectating": true})
			readyAll(t, s.hub, cs[1:])
			now := time.Now()
			action(t, s.hub, cs[0], map[string]any{"type": "start_public_infinity"})
			s.step(now)
			if local {
				if r.infinityActive || s.publicPendingCount != 0 {
					t.Fatal("P2-only unsupported controller silently omitted")
				}
				found := false
				for _, p := range drain(cs[0]) {
					if p["type"] == "error" && strings.Contains(p["message"].(string), "Player 1") {
						found = true
					}
				}
				if !found {
					t.Fatal("missing actionable P2 limitation")
				}
			} else if !r.infinityPublic || s.publicPendingCount != 1 {
				t.Fatal("spectator host could not send combat guest to public Infinity")
			}
		})
	}
}
func TestPublicInfinitySoloLaunchAndPendingExpiry(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	s := newInfiniteServer(h)
	now := time.Now()
	if h.roomWire(r).CanStart {
		t.Fatal("fixture needs a solo fixed room")
	}
	action(t, h, cs[0], map[string]any{"type": "select_public_infinity", "enabled": true})
	if !h.roomWire(r).CanStartPublicInfinity {
		t.Fatal("solo room cannot choose public Infinity")
	}
	launchPublicParty(t, s, cs[0], now)
	s.step(now.Add(reconnectGrace + time.Millisecond))
	if s.publicPendingCount != 0 || len(s.publicPending) != 0 || s.public.players != 0 {
		t.Fatal("unclaimed party places survived launch window")
	}
}

func TestPublicInfinitySelectionResetsConsentAndRestoresFixedSoloOpponents(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	readyAll(t, h, cs)
	action(t, h, cs[0], map[string]any{"type": "select_public_infinity", "enabled": true})
	if !r.infinityPublic || cs[1].player.Ready || h.roomWire(r).CanStartPublicInfinity {
		t.Fatal("selection did not reset guest consent")
	}
	action(t, h, cs[1], map[string]any{"type": "ready", "ready": true})
	action(t, h, cs[0], map[string]any{"type": "select_public_infinity", "enabled": true})
	if !cs[1].player.Ready {
		t.Fatal("unchanged destination reset accepted consent")
	}
	action(t, h, cs[1], map[string]any{"type": "select_public_infinity", "enabled": false})
	if !r.infinityPublic {
		t.Fatal("guest changed party destination")
	}
	action(t, h, cs[1], map[string]any{"type": "leave"})
	action(t, h, cs[0], map[string]any{"type": "select_public_infinity", "enabled": false})
	bots := 0
	for _, p := range r.Players {
		if p != nil && p.Kind == "bot" {
			bots++
			if p.Difficulty != "normal" {
				t.Fatal("fixed fallback used wrong difficulty")
			}
		}
	}
	if r.infinityPublic || bots != 3 || !canStart(r) {
		t.Fatal("returning solo public party to fixed play did not restore opponents")
	}
}

func TestPublicInfinityPendingFailedWelcomeAndReservedLocalRemoval(t *testing.T) {
	s, cs, r := publicPartyFixture(t, true)
	now := time.Now()
	launchPublicParty(t, s, cs[0], now)
	dead := fakeClient()
	s.admit(dead)
	dead.stop()
	if _, reject := s.join(dead, infiniteMessage{Code: r.Code, Token: cs[0].player.Token}, now); reject == "" {
		t.Fatal("dead socket welcomed")
	}
	s.disconnect(dead, now)
	if s.public.players != 0 || s.public.connected != 0 || s.publicPendingCount != 3 {
		t.Fatal("failed welcome consumed or released party places")
	}
	pair, old, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: cs[0].player.Token}, now)
	if reject != "" {
		t.Fatal(reject)
	}
	s.disconnect(old, now)
	action(t, s.hub, cs[0], map[string]any{"type": "spectate", "target": pair.localSeat.ID, "member": pair.localSeat.Member, "spectating": true})
	s.step(now.Add(time.Second))
	resumed, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: r.Code, Token: cs[0].player.Token, Resume: true, Generation: r.infinityGeneration}, now.Add(time.Second))
	if reject != "" || resumed.local != nil || resumed.pilot != pair.pilot || s.public.players != 1 || s.public.connected != 1 || s.privateCount != 0 {
		t.Fatal("reserved P2 removal broke public party accounting")
	}
	resumed.pilot.activeAt = now.Add(-infinitePublicIdle)
	s.step(now.Add(2 * time.Second))
	if s.public.players != 0 || s.public.connected != 0 || s.privateCount != 0 {
		t.Fatal("idle authenticated party pinned public capacity")
	}
}
