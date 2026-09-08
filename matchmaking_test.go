package main

import (
	"encoding/json"
	"fmt"
	mrand "math/rand"
	"strings"
	"sync"
	"testing"
	"time"
)

func mmAction(t *testing.T, h *Hub, c *Client, m any) {
	t.Helper()
	c.msgWindow = time.Time{}
	action(t, h, c, m)
}
func mmRoom(t *testing.T, h *Hub, n int) ([]*Client, *Room) {
	t.Helper()
	cs := []*Client{}
	for i := 0; i < n; i++ {
		c := fakeClient()
		h.addClient(c)
		cs = append(cs, c)
		if i == 0 {
			mmAction(t, h, c, map[string]any{"type": "create", "name": fmt.Sprint("HOST", len(h.rooms))})
		} else {
			mmAction(t, h, c, map[string]any{"type": "join", "code": cs[0].room.Code, "name": fmt.Sprint("Friend", i)})
		}
	}
	return cs, cs[0].room
}
func mmQueue(t *testing.T, h *Hub, cs []*Client, key string) {
	t.Helper()
	mmAction(t, h, cs[0], map[string]any{"type": "queue_join", "queue": key})
	q := cs[0].room.Queue
	if q == nil {
		t.Fatal("queue request rejected", drain(cs[0]))
	}
	for _, c := range cs[1:] {
		mmAction(t, h, c, map[string]any{"type": "queue_accept", "queueId": q.ID, "ready": true})
	}
}
func mmScan(h *Hub) { h.mu.Lock(); defer h.mu.Unlock(); h.tickQueues(time.Now().Add(time.Second)) }
func TestMatchmakingCatalogRules(t *testing.T) {
	if len(queueDefinitions) != 6 {
		t.Fatal("six queues required")
	}
	for _, d := range queueDefinitions {
		t.Run(d.Key, func(t *testing.T) {
			r := queueRules(d)
			if d.Mode == "koth" && (d.Target != 30 || r.ScoreTarget != 30) {
				t.Fatal("Hill matchmaking must default to 30 points in both the catalog and match rules")
			}
			if err := validateRules(r); err != nil {
				t.Fatal(err)
			}
			g := newGame(1)
			g.Rules = r
			c, rows := g.mapDimensions()
			if c != d.Cols || rows != d.Rows {
				t.Fatal("bad map")
			}
			if d.TeamSize > 0 && d.Players != 2*d.TeamSize {
				t.Fatal("bad team size")
			}
			if d.TeamSize == 0 && (d.Players != 8 || r.MapSize != "giant") {
				t.Fatal("FFA must use biggest maze")
			}
		})
	}
}
func TestMatchmakingAllSixQueues(t *testing.T) {
	for _, d := range queueDefinitions {
		t.Run(d.Key, func(t *testing.T) {
			h := newHub(32)
			clients := []*Client{}
			homes := []*Room{}
			for i := 0; i < d.Players; i++ {
				cs, r := mmRoom(t, h, 1)
				clients = append(clients, cs[0])
				homes = append(homes, r)
				mmQueue(t, h, cs, d.Key)
			}
			mmScan(h)
			battle := clients[0].room
			if battle.Match == nil || battle.Game.Phase != "countdown" || len(h.queues) != 0 {
				t.Fatal("match not created")
			}
			if battle.Host != -1 || battle.Game.World.Cols != d.Cols || battle.Game.World.Rows != d.Rows {
				t.Fatal("bad fixed game")
			}
			teams := map[int]int{}
			for i, c := range clients {
				if c.room != battle || c.player.Return == nil || c.player.Kind == "bot" {
					t.Fatal("not transferred")
				}
				teams[c.player.Team]++
				if !homes[i].hasAway() || homes[i].Players[0].Client != nil {
					t.Fatal("home not reserved")
				}
			}
			if d.TeamSize > 0 && (teams[1] != d.TeamSize || teams[2] != d.TeamSize) {
				t.Fatal("unbalanced teams", teams)
			}
			if d.TeamSize == 0 && teams[0] != 8 {
				t.Fatal("FFA alliance")
			}
			mmAction(t, h, clients[0], map[string]any{"type": "return_party"})
			if clients[0].room != homes[0] || homes[0].hasAway() {
				t.Fatal("return failed")
			}
		})
	}
}
func TestMatchmakingPartyConsentAndNoSplit(t *testing.T) {
	h := newHub(20)
	a, home := mmRoom(t, h, 2)
	b, _ := mmRoom(t, h, 1)
	c, _ := mmRoom(t, h, 3)
	mmAction(t, h, a[0], map[string]any{"type": "queue_join", "queue": "ctf-3"})
	q := home.Queue
	if !q.Enqueued.IsZero() {
		t.Fatal("remote consent skipped")
	}
	mmQueue(t, h, b, "ctf-3")
	mmQueue(t, h, c, "ctf-3")
	mmScan(h)
	if a[0].room.Match != nil || b[0].room.Match != nil {
		t.Fatal("unconfirmed party matched")
	}
	mmAction(t, h, a[1], map[string]any{"type": "queue_accept", "queueId": q.ID, "ready": true})
	h.nextQueueScan = time.Time{}
	mmScan(h)
	if a[0].room.Match == nil || a[0].room != a[1].room || a[0].player.Team != a[1].player.Team || a[0].player.Team == c[0].player.Team || b[0].player.Team != a[0].player.Team {
		t.Fatal("party split or not packed")
	}
}
func TestMatchmakingRejectsOversizedAndFFAParties(t *testing.T) {
	for _, x := range []struct {
		n   int
		key string
	}{{4, "elimination-3"}, {2, "elimination-1"}, {3, "elimination-2"}, {2, "ffa-8"}} {
		h := newHub(10)
		cs, r := mmRoom(t, h, x.n)
		mmAction(t, h, cs[0], map[string]any{"type": "queue_join", "queue": x.key})
		if r.Queue != nil || len(h.queues) != 0 {
			t.Fatal("invalid party accepted", x)
		}
	}
}
func TestMatchmakingIgnoresBotsAndViewers(t *testing.T) {
	h := newHub(12)
	cs, home := mmRoom(t, h, 1)
	for i := 0; i < 5; i++ {
		mmAction(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "normal", "team": 0})
	}
	viewer := fakeClient()
	h.addClient(viewer)
	mmAction(t, h, viewer, map[string]any{"type": "join", "code": home.Code, "name": "Audience", "spectating": true})
	mmQueue(t, h, cs, "elimination-1")
	if len(home.Queue.Pilots) != 1 {
		t.Fatal("bot/viewer counted")
	}
	h.removeClient(viewer)
	if home.Queue == nil {
		t.Fatal("unrelated spectator cancelled search")
	}
	enemy, _ := mmRoom(t, h, 1)
	mmQueue(t, h, enemy, "elimination-1")
	mmScan(h)
	if len(home.Players) != 8 || cs[0].room.Match == nil {
		t.Fatal("didn't match")
	}
	n := 0
	for _, p := range home.Players {
		if p != nil && p.Kind == "bot" {
			n++
		}
	}
	if n != 5 {
		t.Fatal("bots lost")
	}
	for _, p := range cs[0].room.Players {
		if p != nil && p.Kind == "bot" {
			t.Fatal("bot backfill")
		}
	}
}
func TestMatchmakingGuestCannotQueueKickOrEdit(t *testing.T) {
	h := newHub(20)
	cs, r := mmRoom(t, h, 2)
	mmAction(t, h, cs[1], map[string]any{"type": "queue_join", "queue": "elimination-2"})
	if r.Queue != nil {
		t.Fatal("guest queued")
	}
	mmQueue(t, h, cs, "elimination-2")
	q := r.Queue
	for _, typ := range []string{"start", "rules", "add", "configure", "preset", "lobby", "swap"} {
		mmAction(t, h, cs[0], map[string]any{"type": typ})
		if r.Queue != q || r.Game.Phase != "lobby" {
			t.Fatal("setup mutated", typ)
		}
	}
	enemy, _ := mmRoom(t, h, 2)
	mmQueue(t, h, enemy, "elimination-2")
	mmScan(h)
	battle := cs[0].room
	for _, typ := range []string{"start", "rules", "add", "configure", "preset", "lobby", "swap", "kick", "ready"} {
		mmAction(t, h, cs[0], map[string]any{"type": typ, "target": enemy[0].player.ID, "member": enemy[0].player.Member})
		if cs[0].room != battle || enemy[0].room != battle || battle.Game.Phase != "countdown" {
			t.Fatal("public match hijacked", typ)
		}
	}
}
func TestMatchmakingCancelAndStaleConsent(t *testing.T) {
	h := newHub(10)
	cs, r := mmRoom(t, h, 2)
	mmQueue(t, h, cs, "ctf-3")
	old := r.Queue.ID
	mmAction(t, h, cs[1], map[string]any{"type": "queue_cancel", "queueId": old})
	if r.Queue != nil || len(h.queues) != 0 {
		t.Fatal("cancel didn't remove ticket")
	}
	mmAction(t, h, cs[0], map[string]any{"type": "queue_join", "queue": "koth-3"})
	q := r.Queue
	mmAction(t, h, cs[1], map[string]any{"type": "queue_accept", "queueId": old, "ready": true})
	if !q.Enqueued.IsZero() {
		t.Fatal("stale accept")
	}
	mmAction(t, h, cs[1], map[string]any{"type": "queue_cancel", "queueId": old})
	if r.Queue != q {
		t.Fatal("stale cancel")
	}
	mmAction(t, h, cs[1], map[string]any{"type": "queue_accept", "queueId": q.ID, "ready": false})
	if r.Queue != nil {
		t.Fatal("decline ignored")
	}
}
func TestMatchmakingDisconnectCancelsParty(t *testing.T) {
	h := newHub(12)
	cs, r := mmRoom(t, h, 2)
	mmQueue(t, h, cs, "ctf-3")
	h.removeClient(cs[1])
	if r.Queue != nil {
		t.Fatal("disconnected party still searching")
	}
	next := fakeClient()
	h.addClient(next)
	mmAction(t, h, next, map[string]any{"type": "join", "code": r.Code, "token": cs[1].player.Token})
	if next.room != r || r.Queue != nil {
		t.Fatal("resume changed queue")
	}
}
func TestMatchmakingQueuedNewJoinIsViewer(t *testing.T) {
	h := newHub(10)
	cs, r := mmRoom(t, h, 1)
	mmQueue(t, h, cs, "elimination-2")
	other := fakeClient()
	h.addClient(other)
	mmAction(t, h, other, map[string]any{"type": "join", "code": r.Code, "name": "Late"})
	if !other.player.Spectating || len(r.Queue.Pilots) != 1 {
		t.Fatal("party changed underneath queue")
	}
}
func TestMatchmakingP2TransferReturnAndControls(t *testing.T) {
	h := newHub(15)
	cs, home := mmRoom(t, h, 1)
	mmAction(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "KEYBOARD TWO", "team": 0})
	second := home.Players[1]
	mmQueue(t, h, cs, "elimination-2")
	enemy, _ := mmRoom(t, h, 2)
	mmQueue(t, h, enemy, "elimination-2")
	mmScan(h)
	battle := cs[0].room
	var child *Player
	for _, p := range battle.Players {
		if p != nil && p.Kind == "local" {
			child = p
		}
	}
	if child == nil || child.Controller != cs[0].player || child.Owner != cs[0].player.ID || child.Team != cs[0].player.Team {
		t.Fatal("P2 ownership/team lost")
	}
	mmAction(t, h, cs[0], map[string]any{"type": "input", "player": child.ID, "room": battle.Code, "seq": 1, "forward": true, "fire": true})
	if !child.Input.Forward || !child.FirePending {
		t.Fatal("P2 controls lost")
	}
	mmAction(t, h, enemy[0], map[string]any{"type": "input", "player": child.ID, "seq": 99, "reverse": true})
	if child.Input.Seq != 1 {
		t.Fatal("foreign controller took P2")
	}
	mmAction(t, h, cs[0], map[string]any{"type": "return_party"})
	if cs[0].room != home || home.Players[1] != second || second.Owner != cs[0].player.ID || second.Controller != cs[0].player || home.hasAway() {
		t.Fatal("P2 not restored")
	}
	if enemy[0].room.Game.Phase != "matchOver" {
		t.Fatal("abandoned opponent side did not forfeit")
	}
}
func TestMatchmakingSpectatingControllerCanQueueP2(t *testing.T) {
	h := newHub(12)
	cs, home := mmRoom(t, h, 1)
	mmAction(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "P2", "team": 0})
	mmAction(t, h, cs[0], map[string]any{"type": "spectate", "spectating": true})
	mmQueue(t, h, cs, "elimination-1")
	enemy, _ := mmRoom(t, h, 1)
	mmQueue(t, h, enemy, "elimination-1")
	mmScan(h)
	if !cs[0].player.Spectating || cs[0].room.Match == nil {
		t.Fatal("controller didn't travel as viewer")
	}
	mmAction(t, h, cs[0], map[string]any{"type": "return_party"})
	if cs[0].room != home || !cs[0].player.Spectating || home.hasAway() {
		t.Fatal("original spectator role lost")
	}
}
func TestMatchmakingResumeBothHandoffs(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	b, _ := mmRoom(t, h, 1)
	code, token := home.Code, a[0].player.Token
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	battle := a[0].room
	h.removeClient(a[0])
	c := fakeClient()
	h.addClient(c)
	mmAction(t, h, c, map[string]any{"type": "join", "code": code, "token": token})
	if c.room != battle {
		t.Fatal("lost match welcome couldn't resume")
	}
	mmAction(t, h, c, map[string]any{"type": "return_party"})
	h.removeClient(c)
	next := fakeClient()
	h.addClient(next)
	mmAction(t, h, next, map[string]any{"type": "join", "code": battle.Code, "token": token})
	if next.room != home {
		t.Fatal("lost return welcome couldn't resume")
	}
}
func TestMatchmakingReservationsSurviveGrace(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	b, _ := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	h.tick(time.Now().Add(25 * time.Second))
	if h.rooms[home.Code] != home || home.Players[0] == nil || home.Players[0].Away == nil {
		t.Fatal("away party expired as disconnected")
	}
}
func TestMatchmakingLeaveReleasesHome(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	b, _ := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	mmAction(t, h, a[0], map[string]any{"type": "leave"})
	if home.hasAway() || home.Players[0] != nil || a[0].room != nil {
		t.Fatal("reservation leaked")
	}
	h.tick(time.Now())
	if h.rooms[home.Code] != nil {
		t.Fatal("empty home leaked")
	}
}
func TestMatchmakingExpiredControllerReleasesP2(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	mmAction(t, h, a[0], map[string]any{"type": "add", "kind": "local", "team": 0})
	b, _ := mmRoom(t, h, 2)
	mmQueue(t, h, a, "elimination-2")
	mmQueue(t, h, b, "elimination-2")
	mmScan(h)
	h.removeClient(a[0])
	h.tick(time.Now().Add(22 * time.Second))
	if home.hasAway() || home.Players[0] != nil || home.Players[1] != nil {
		t.Fatal("expired controller left reserved child")
	}
}
func TestMatchmakingCapacityDoesNotConsumeTickets(t *testing.T) {
	h := newHub(2)
	a, ar := mmRoom(t, h, 1)
	b, br := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	if a[0].room != ar || b[0].room != br || len(h.queues) != 2 || ar.Queue == nil {
		t.Fatal("capacity lost players/tickets")
	}
	h.maxRooms = 3
	h.nextQueueScan = time.Time{}
	mmScan(h)
	if a[0].room.Match == nil {
		t.Fatal("didn't recover after capacity")
	}
}
func TestMatchmakingNoCombatAdmissionOrOldInput(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	b, _ := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	battle := a[0].room
	mmAction(t, h, a[0], map[string]any{"type": "input", "room": home.Code, "seq": 999, "fire": true})
	if a[0].player.Input.Seq != 0 {
		t.Fatal("old room input leaked")
	}
	other := fakeClient()
	h.addClient(other)
	mmAction(t, h, other, map[string]any{"type": "join", "code": battle.Code, "name": "Watcher"})
	if !other.player.Spectating {
		t.Fatal("outsider took match tank")
	}
	mmAction(t, h, other, map[string]any{"type": "spectate", "spectating": false})
	if !other.player.Spectating {
		t.Fatal("watcher promoted in queue match")
	}
	mmAction(t, h, other, map[string]any{"type": "return_party"})
	if other.room != battle {
		t.Fatal("outsider stole return reservation")
	}
}
func TestMatchmakingPrivateRulesAndBotsRestored(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	home.Game.Rules.TeamMode = "teams"
	home.Game.Rules.TeamNames = []string{"Custom", "Friends", "Other", "Last"}
	home.Game.Rules.MapSize = "giant"
	home.Game.Rules.FriendlyFire = true
	a[0].player.Team = 4
	mmAction(t, h, a[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "hard", "name": "Bot friend", "team": 4})
	bot := home.Players[1]
	b, _ := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	if a[0].room.Game.Rules.FriendlyFire || a[0].room.Game.Rules.MapSize != "compact" {
		t.Fatal("private rules contaminated public match")
	}
	mmAction(t, h, a[0], map[string]any{"type": "return_party"})
	if a[0].player.Team != 4 || home.Game.Rules.MapSize != "giant" || !home.Game.Rules.FriendlyFire || home.Players[1] != bot {
		t.Fatal("private setup lost")
	}
}
func TestMatchmakingQueuePackingProperty(t *testing.T) {
	d, _ := queueDefinition("elimination-3")
	rng := mrand.New(mrand.NewSource(31))
	for run := 0; run < 600; run++ {
		pool := []*QueueTicket{}
		n := 1 + rng.Intn(12)
		for i := 0; i < n; i++ {
			pool = append(pool, &QueueTicket{ID: uint64(i + 1), Pilots: make([]*Player, 1+rng.Intn(3)), Enqueued: time.Unix(int64(i), 0)})
		}
		feasible := [4][4]bool{}
		feasible[0][0] = true
		for _, q := range pool {
			size := len(q.Pilots)
			for a := 3; a >= 0; a-- {
				for b := 3; b >= 0; b-- {
					if feasible[a][b] {
						if a+size <= 3 {
							feasible[a+size][b] = true
						}
						if b+size <= 3 {
							feasible[a][b+size] = true
						}
					}
				}
			}
		}
		sides := packQueue(pool, d, rng)
		found := len(sides[0]) > 0
		if found != feasible[3][3] {
			t.Fatal("incomplete packing", run)
		}
		seen := map[uint64]bool{}
		if found {
			for _, side := range sides {
				sum := 0
				for _, q := range side {
					if seen[q.ID] {
						t.Fatal("party reused")
					}
					seen[q.ID] = true
					sum += len(q.Pilots)
				}
				if sum != 3 {
					t.Fatal("bad side size")
				}
			}
		}
	}
}
func TestMatchmakingNoPrivateDataInBroadcasts(t *testing.T) {
	h := newHub(12)
	a, _ := mmRoom(t, h, 1)
	b, _ := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	for _, c := range append(a, b...) {
		for _, packet := range drain(c) {
			if packet["type"] == "welcome" {
				continue
			}
			data, _ := json.Marshal(packet)
			for _, other := range append(a, b...) {
				if strings.Contains(string(data), other.player.Token) {
					t.Fatal("credential leaked")
				}
			}
		}
	}
}
func TestMatchmakingConcurrentEntrySingleAssignment(t *testing.T) {
	h := newHub(32)
	clients := []*Client{}
	for i := 0; i < 16; i++ {
		cs, _ := mmRoom(t, h, 1)
		clients = append(clients, cs[0])
	}
	var wg sync.WaitGroup
	for _, c := range clients {
		wg.Add(1)
		go func(c *Client) {
			defer wg.Done()
			data := []byte(`{"type":"queue_join","queue":"elimination-1"}`)
			if err := h.handle(c, data, time.Now()); err != nil {
				t.Error(err)
			}
		}(c)
	}
	wg.Wait()
	h.tick(time.Now().Add(time.Second))
	h.tick(time.Now().Add(2 * time.Second))
	matches := map[*Room]int{}
	for _, c := range clients {
		if c.room.Match == nil {
			t.Fatal("not assigned")
		}
		matches[c.room]++
	}
	if len(matches) != 8 {
		t.Fatal("duplicate or missed rooms")
	}
	for _, n := range matches {
		if n != 2 {
			t.Fatal("double assigned")
		}
	}
}

func TestMatchmakingTwoKeyboardParties(t *testing.T) {
	h := newHub(20)
	controllers := []*Client{}
	homes := []*Room{}
	for i := 0; i < 2; i++ {
		cs, r := mmRoom(t, h, 1)
		controllers = append(controllers, cs[0])
		homes = append(homes, r)
		mmAction(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": fmt.Sprint("P2-", i), "team": 0})
		mmQueue(t, h, cs, "elimination-2")
	}
	mmScan(h)
	battle := controllers[0].room
	if battle.Match == nil || controllers[1].room != battle {
		t.Fatal("match missing")
	}
	children := []*Player{}
	for _, c := range controllers {
		var child *Player
		for _, p := range battle.Players {
			if p != nil && p.Kind == "local" && p.Controller == c.player {
				child = p
			}
		}
		if child == nil || child.Owner != c.player.ID || child.Team != c.player.Team {
			t.Fatal("independent controller association lost")
		}
		children = append(children, child)
		mmAction(t, h, c, map[string]any{"type": "input", "player": child.ID, "seq": 7, "forward": true, "fire": true})
	}
	if children[0].Controller == children[1].Controller || children[0].Team == children[1].Team {
		t.Fatal("opposing parties merged")
	}
	mmAction(t, h, controllers[0], map[string]any{"type": "input", "player": children[1].ID, "seq": 99, "reverse": true})
	if children[1].Input.Seq != 7 || !children[0].FirePending || !children[1].FirePending {
		t.Fatal("input ownership crossed parties")
	}
	for i, c := range controllers {
		mmAction(t, h, c, map[string]any{"type": "return_party"})
		if c.room != homes[i] || homes[i].hasAway() || homes[i].Players[1].Controller != c.player {
			t.Fatal("P2 return incorrect")
		}
	}
}
func TestMatchmakingIdleCleanupReleasesOrigins(t *testing.T) {
	h := newHub(20)
	a, ah := mmRoom(t, h, 1)
	b, bh := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	battle := a[0].room
	battle.LastAction = time.Now().Add(-roomIdleLimit - time.Minute)
	h.tick(time.Now())
	if h.rooms[battle.Code] != nil || ah.hasAway() || bh.hasAway() || ah.member(0) != nil || bh.member(0) != nil {
		t.Fatal("idle battle leaked reserved private members")
	}
}
func TestMatchmakingUnconfirmedInviteExpires(t *testing.T) {
	h := newHub(12)
	cs, r := mmRoom(t, h, 2)
	mmAction(t, h, cs[0], map[string]any{"type": "queue_join", "queue": "elimination-2"})
	r.Queue.Created = time.Now().Add(-3 * time.Minute)
	mmScan(h)
	if r.Queue != nil || len(h.queues) != 0 || cs[0].room != r || cs[1].room != r {
		t.Fatal("expired invitation did not release search")
	}
}
func TestMatchmakingUnrelatedSpectatorDisconnectPreservesQueue(t *testing.T) {
	h := newHub(12)
	cs, r := mmRoom(t, h, 1)
	viewer := fakeClient()
	h.addClient(viewer)
	mmAction(t, h, viewer, map[string]any{"type": "join", "code": r.Code, "name": "Viewer", "spectating": true})
	mmQueue(t, h, cs, "elimination-3")
	h.removeClient(viewer)
	mmScan(h)
	if r.Queue == nil || r.Queue.Enqueued.IsZero() {
		t.Fatal("spectator cancelled someone else's search")
	}
}
func BenchmarkMatchmakingIncompatibleParties(b *testing.B) {
	d, _ := queueDefinition("elimination-3")
	pool := make([]*QueueTicket, 256)
	for i := range pool {
		pool[i] = &QueueTicket{ID: uint64(i + 1), Pilots: make([]*Player, 2), Enqueued: time.Unix(int64(i), 0)}
	}
	rng := mrand.New(mrand.NewSource(1))
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if v := packQueue(pool, d, rng); len(v[0]) > 0 {
			b.Fatal("split party")
		}
	}
}
