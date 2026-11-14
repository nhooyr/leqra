package main

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func spectatorRoomClient(t *testing.T, s *infiniteServer, room *Room, name string) *Client {
	t.Helper()
	c := fakeClient()
	s.hub.addClient(c)
	action(t, s.hub, c, map[string]any{"type": "join", "code": room.Code, "name": name, "spectating": true})
	if c.player == nil || !c.player.Spectating {
		t.Fatal("spectator fixture could not join the room", drain(c))
	}
	drain(c)
	return c
}

func joinRoomObserver(t *testing.T, s *infiniteServer, room *Room, viewer *Client, now time.Time) (infiniteConnection, *Client) {
	t.Helper()
	c := partySnapshotClient()
	if !s.admit(c) {
		t.Fatal("observer transport was not admitted")
	}
	connection, rejection := s.join(c, infiniteMessage{Code: room.Code, Token: viewer.player.Token, Spectating: true}, now)
	if rejection != "" {
		t.Fatal("observer join failed", rejection)
	}
	return connection, c
}

func TestRoomInfinitySpectatorAuthenticatesRoleWithoutAllocatingTankOrAccount(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	viewer := spectatorRoomClient(t, s, room, "Viewer")
	a := pair.arena
	players, connected, nextID, privateCount, claims := a.players, a.connected, a.nextID, s.privateCount, len(s.hub.callsigns.claims)
	connection, c := joinRoomObserver(t, s, room, viewer, now)
	if connection.pilot != nil || connection.local != nil || connection.observer == nil || connection.arena != a ||
		a.players != players || a.connected != connected || a.nextID != nextID || s.privateCount != privateCount || len(s.hub.callsigns.claims) != claims {
		t.Fatal("spectator allocated combat authority or an account")
	}
	packets := drain(c)
	if len(packets) != 1 || packets[0]["spectating"] != true || packets[0]["id"] != float64(0) || packets[0]["following"] != float64(pair.pilot.ID) || packets[0]["publicToken"] != nil || packets[0]["localId"] != nil {
		t.Fatal("spectator welcome leaked ownership or omitted read-only identity", packets)
	}
	for _, request := range []infiniteMessage{
		{Code: room.Code, Token: members[0].player.Token, Spectating: true},
		{Code: room.Code, Token: "forged", Spectating: true},
		{Code: "another room", Token: viewer.player.Token, Spectating: true},
		{Token: viewer.player.Token, Spectating: true},
		{PublicToken: viewer.player.PublicToken, Spectating: true},
		{Code: room.Code, Token: viewer.player.Token},
	} {
		if other, _, rejection := tryInfinityReconnect(t, s, request, now); rejection == "" || other.pilot != nil || other.observer != nil {
			t.Fatal("forged or incorrect role obtained arena access", request.Code)
		}
	}
	if a.players != players || a.connected != connected || s.public.players != 0 {
		t.Fatal("rejected spectator admission changed player counts")
	}
}

func TestRoomInfinitySpectatorFullLeaderboardFarFollowDeathAndRemoval(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	connection, controller, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	controller.updates = make(chan snapshotFrame, 1)
	a := connection.arena
	for i := range 12 {
		bot := a.addPilot(fmt.Sprintf("Room Bot %d", i), true, 0, 0, 0, 0)
		bot.Score = 50 - i
	}
	target := a.pilots[len(a.pilots)-1]
	target.X, target.Y, target.HP, target.respawn = 50000, -70000, 0, a.tick+60
	target.KilledByColor = "private-death-color"
	viewer := spectatorRoomClient(t, s, room, "Watching")
	_, c := joinRoomObserver(t, s, room, viewer, now)
	drain(c)
	s.follow(c, target.ID, now)
	state := readPartySnapshot(t, c)
	if !state.Spectating || state.Following != target.ID || len(state.Leaders) != 13 || len(state.Tanks) != 1 || state.Tanks[0].ID != target.ID || state.Tanks[0].HP != 0 || state.Tanks[0].X != target.X || state.Tanks[0].Y != target.Y || state.Tanks[0].KilledByColor != "" {
		t.Fatalf("full standings or far dead-target view is incorrect: %+v", state)
	}
	if player := readPartySnapshot(t, controller); player.Spectating || player.Following != 0 || len(player.Leaders) != infiniteLeaderCount {
		t.Fatal("observer changed ordinary player leaderboard or cached-view role")
	}
	if replies := drain(c); len(replies) != 1 || replies[0]["type"] != "followed" || replies[0]["following"] != float64(target.ID) {
		t.Fatal("follow did not acknowledge the authoritative target", replies)
	}
	for _, id := range []int{-1, 0, target.ID + 100000} {
		s.follow(c, id, now)
		if !hasError(c, "follow_invalid") || s.connections[c].observer.following != target.ID {
			t.Fatal("invalid target changed the selected identity")
		}
	}
	s.follow(controller, target.ID, now)
	if !hasError(controller, "follow_invalid") {
		t.Fatal("a combat controller acquired spectator follow authority")
	}
	target.HP = infiniteMaxHP
	a.mu.Lock()
	a.broadcast()
	a.mu.Unlock()
	if next := readPartySnapshot(t, c); next.Following != target.ID || next.Tanks[0].HP != infiniteMaxHP {
		t.Fatal("respawn lost the followed identity")
	}
	a.pilots = a.pilots[:len(a.pilots)-1]
	a.mu.Lock()
	a.broadcast()
	a.mu.Unlock()
	if next := readPartySnapshot(t, c); next.Following != a.pilots[1].ID || len(next.Leaders) != 12 {
		t.Fatal("removed target did not fall back to the highest ranked current tank")
	}
}

func TestRoomInfinitySpectatorReconnectAndRoleRevocation(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	viewer := spectatorRoomClient(t, s, room, "Resume Viewer")
	connection, c := joinRoomObserver(t, s, room, viewer, now)
	s.follow(c, pair.local.ID, now)
	s.disconnect(c, now)
	request := infiniteMessage{Code: room.Code, Token: viewer.player.Token, Spectating: true, Resume: true, Generation: room.infinityGeneration}
	resumed, next, rejection := tryInfinityReconnect(t, s, request, now.Add(time.Second))
	if rejection != "" || resumed.observer != connection.observer || resumed.observer.following != pair.local.ID || len(pair.arena.observers) != 1 || s.privateCount != 2 || pair.arena.players != 2 {
		t.Fatal("spectator reconnect lost its view or allocated a body", rejection)
	}
	drain(next)
	request.Target = pair.pilot.ID
	replacement, third, rejection := tryInfinityReconnect(t, s, request, now.Add(2*time.Second))
	if rejection != "" || replacement.observer.following != pair.pilot.ID || len(pair.arena.observers) != 1 {
		t.Fatal("explicit reconnect target or duplicate replacement failed", rejection)
	}
	s.disconnect(next, now.Add(2*time.Second))
	if len(pair.arena.observers) != 1 {
		t.Fatal("stale old close removed the replacement observer")
	}
	drain(third)
	action(t, s.hub, viewer, map[string]any{"type": "spectate", "spectating": false})
	s.step(now.Add(3 * time.Second))
	if _, exists := s.connections[third]; exists || len(pair.arena.observers) != 0 || !hasError(third, "room_access_changed") {
		t.Fatal("promotion retained stale spectator transport authority")
	}
}

func TestRoomInfinityEmptySpectatorAndEndedGeneration(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	viewer := spectatorRoomClient(t, s, room, "Empty Viewer")
	connection, c := joinRoomObserver(t, s, room, viewer, now)
	state := readPartySnapshot(t, c)
	if state.Following != 0 || len(state.Tanks) != 0 || len(state.Leaders) != 0 || state.Players != 0 || state.TankCount != 0 || connection.arena.players != 0 || connection.arena.nextID != 0 {
		t.Fatal("empty observer arena invented a tank or follow target")
	}
	pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" || pair.arena != connection.arena {
		t.Fatal("first real controller did not reuse the observed arena", rejection)
	}
	pair.arena.mu.Lock()
	pair.arena.broadcast()
	pair.arena.mu.Unlock()
	if state := readPartySnapshot(t, c); state.Following != pair.pilot.ID || len(state.Tanks) == 0 {
		t.Fatal("first real player did not become the default follow target")
	}
	drain(c)
	action(t, s.hub, members[0], map[string]any{"type": "lobby"})
	s.step(now.Add(time.Second))
	if len(pair.arena.observers) != 0 || !hasError(c, "room_access_changed") {
		t.Fatal("ended generation retained an observer")
	}
	if _, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: viewer.player.Token, Spectating: true, Resume: true, Generation: room.infinityGeneration}, now); rejection != infiniteResumeExpired {
		t.Fatal("ended run resumed as an observer", rejection)
	}
}

func TestRoomInfinitySpectatorSnapshotNeverContainsCredentials(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	viewer := spectatorRoomClient(t, s, room, "Private View")
	_, c := joinRoomObserver(t, s, room, viewer, now)
	state := readPartySnapshot(t, c)
	data, _ := json.Marshal(state)
	for _, secret := range []string{members[0].player.Token, pair.pilot.publicToken, pair.local.publicToken, viewer.player.Token, viewer.player.PublicToken} {
		if secret != "" && strings.Contains(string(data), secret) {
			t.Fatal("spectator snapshot leaked a private credential")
		}
	}
}

func TestRoomInfinitySpectatorRoleChangesBeforeNextSimulationTick(t *testing.T) {
	for _, disconnected := range []bool{false, true} {
		t.Run(fmt.Sprint("promote reserved=", disconnected), func(t *testing.T) {
			s, members, room := startInfinityReconnectRoom(t, 1, false)
			now := time.Now()
			pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
			if rejection != "" {
				t.Fatal(rejection)
			}
			viewer := spectatorRoomClient(t, s, room, "Promoted")
			_, c := joinRoomObserver(t, s, room, viewer, now)
			if disconnected {
				s.disconnect(c, now)
			}
			action(t, s.hub, viewer, map[string]any{"type": "spectate", "spectating": false})
			player, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: viewer.player.Token}, now)
			if rejection != "" || player.pilot == nil || player.observer != nil || player.arena != pair.arena || len(pair.arena.observers) != 0 || pair.arena.players != 2 {
				t.Fatal("promotion resumed a nonexistent body or left observer authority", rejection)
			}
		})
	}
	t.Run("demote active controller", func(t *testing.T) {
		s, members, room := startInfinityReconnectRoom(t, 1, false)
		now := time.Now()
		pair, old, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
		if rejection != "" {
			t.Fatal(rejection)
		}
		pair.arena.setConnectionInput(old, pair.pilot, pair.pilot, Input{Forward: true, Fire: true}, false, now)
		action(t, s.hub, members[0], map[string]any{"type": "spectate", "spectating": true})
		observer, _ := joinRoomObserver(t, s, room, members[0], now)
		pair.arena.setConnectionInput(old, pair.pilot, pair.pilot, Input{Forward: true, Fire: true}, false, now)
		if pair.pilot.client != nil || pair.arena.players != 0 || len(pair.arena.pilots) != 0 || observer.arena != pair.arena || !hasError(old, "room_access_changed") {
			t.Fatal("demotion left the previous body controllable or changed the observed maze")
		}
	})
}

func TestRoomInfinitySpectatorKeepsEmptyArenaForNextRealController(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	pair, old, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	viewer := spectatorRoomClient(t, s, room, "Waiting")
	_, observer := joinRoomObserver(t, s, room, viewer, now)
	s.remove(old)
	s.step(now)
	if state := readPartySnapshot(t, observer); state.Following != 0 || state.TankCount != 0 || len(state.Leaders) != 0 {
		t.Fatal("last controller departure retained a phantom actor")
	}
	if s.private[infiniteRoom{room, room.infinityGeneration}] != pair.arena {
		t.Fatal("last controller detached the still-observed private arena")
	}
	newPair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" || newPair.arena != pair.arena {
		t.Fatal("returning controller created another maze under the spectator", rejection)
	}
	newPair.arena.mu.Lock()
	newPair.arena.broadcast()
	newPair.arena.mu.Unlock()
	if state := readPartySnapshot(t, observer); state.Following != newPair.pilot.ID {
		t.Fatal("waiting spectator did not follow the returning real tank")
	}
}

func TestRoomInfinitySpectatorAccountRotationRevokesViewImmediately(t *testing.T) {
	s, _, room := startInfinityReconnectRoom(t, 1, false)
	viewer := spectatorRoomClient(t, s, room, "Key Viewer")
	_, c := joinRoomObserver(t, s, room, viewer, time.Now())
	oldKey, roomToken := viewer.player.PublicToken, viewer.player.Token
	if _, err := s.rotateAccount(oldKey, freshAccountKey(t)); err != nil {
		t.Fatal(err)
	}
	if _, exists := s.connections[c]; exists || !hasError(c, "account_key_revoked") {
		t.Fatal("rotated spectator account retained its live view")
	}
	if _, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: roomToken, Spectating: true}, time.Now()); rejection == "" {
		t.Fatal("revoked room token regained spectator access")
	}
}

func TestRoomInfinitySpectatorWebSocketFollowPingAndReadOnlyCommands(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	viewer := spectatorRoomClient(t, s, room, "Wire Viewer")
	app := newApp(4, nil)
	app.infinite.close()
	app.hub, app.infinite = s.hub, s
	t.Cleanup(s.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	c, reader := dialInfinite(t, server.URL, map[string]any{"type": "join", "version": version, "code": room.Code, "token": viewer.player.Token, "spectating": true, "target": pair.pilot.ID}, false)
	var welcome map[string]any
	readInfinitePacket(t, reader, &welcome)
	if welcome["spectating"] != true || welcome["following"] != float64(pair.pilot.ID) || welcome["publicToken"] != nil {
		t.Fatal("real WebSocket did not authenticate a read-only observer", welcome)
	}
	var state infiniteSnapshot
	readInfinitePacket(t, reader, &state)
	if !state.Spectating || state.Following != pair.pilot.ID {
		t.Fatal("initial observer state was not delivered after welcome")
	}
	readReply := func(kind string) map[string]any {
		t.Helper()
		for range 10 {
			var packet map[string]any
			readInfinitePacket(t, reader, &packet)
			if packet["type"] == kind {
				return packet
			}
		}
		t.Fatal("missing reply", kind)
		return nil
	}
	write := func(packet string) {
		t.Helper()
		if _, err := c.Write(maskedFrame(1, true, []byte(packet))); err != nil {
			t.Fatal(err)
		}
	}
	write(fmt.Sprintf(`{"type":"follow","target":%d}`, pair.pilot.ID))
	if reply := readReply("followed"); reply["following"] != float64(pair.pilot.ID) {
		t.Fatal("real follow acknowledgement lost its target")
	}
	write(`{"type":"follow","target":999999}`)
	if reply := readReply("error"); reply["code"] != "follow_invalid" || reply["action"] != "follow" {
		t.Fatal("invalid target lacked a safe recoverable error", reply)
	}
	write(`{"type":"rename","requestId":1,"name":"FORGED"}`)
	if reply := readReply("rename_error"); reply["code"] != "spectator_read_only" {
		t.Fatal("spectator renamed a combat tank", reply)
	}
	write(`{"type":"ping","t":123.25}`)
	if reply := readReply("pong"); reply["t"] != 123.25 {
		t.Fatal("spectator lost ordinary transport heartbeats")
	}
	write(`{"type":"input","seq":999,"forward":true,"fire":true,"score":999999}`)
	if code := readInfinityPingClose(t, reader); code != 1008 {
		t.Fatal("spectator input did not close with a policy error", code)
	}
	pair.arena.mu.Lock()
	defer pair.arena.mu.Unlock()
	if pair.pilot.input.Forward || pair.pilot.input.Fire || pair.pilot.Score != 0 || pair.pilot.Name == "FORGED" {
		t.Fatal("read-only wire commands mutated the followed tank")
	}
}

func TestRoomInfinitySpectatorGalleryDoesNotIncreaseRoamingBudget(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	a := pair.arena
	a.rules.randomBots = true
	var client *Client
	for i := range maxSpectators {
		viewer := spectatorRoomClient(t, s, room, fmt.Sprintf("Observer %d", i))
		_, client = joinRoomObserver(t, s, room, viewer, now)
	}
	if a.players != 2 || a.connected != 2 || a.nextID != 2 || s.privateCount != 2 || a.roamingBotBudget() != 16 {
		t.Fatal("a full spectator gallery increased combat capacity or bot population")
	}
	for range 16 {
		a.tick = a.nextBot
		a.populate()
	}
	a.mu.Lock()
	a.broadcast()
	a.mu.Unlock()
	if state := readPartySnapshot(t, client); len(state.Leaders) != 18 || state.Players != 2 || state.TankCount != 18 {
		t.Fatal("real roaming population did not produce a full scrollable leaderboard", len(state.Leaders), state.Players, state.TankCount)
	}
}

func TestRoomInfinitySpectatorKickDepartureAndUnshareRevokeViews(t *testing.T) {
	for _, event := range []string{"kick", "leave", "unshare"} {
		t.Run(event, func(t *testing.T) {
			s, members, room := startInfinityReconnectRoom(t, 1, false)
			now := time.Now()
			pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
			if rejection != "" {
				t.Fatal(rejection)
			}
			viewer := spectatorRoomClient(t, s, room, "Removed Viewer")
			_, c := joinRoomObserver(t, s, room, viewer, now)
			readPartySnapshot(t, c)
			drain(c)
			other := spectatorRoomClient(t, s, room, "Other Viewer")
			_, remaining := joinRoomObserver(t, s, room, other, now)
			readPartySnapshot(t, c)
			switch event {
			case "kick":
				action(t, s.hub, members[0], kickRequest(viewer.player))
			case "leave":
				action(t, s.hub, viewer, map[string]any{"type": "leave"})
			case "unshare":
				action(t, s.hub, members[0], map[string]any{"type": "lobby"})
				action(t, s.hub, members[0], map[string]any{"type": "unshare"})
			}
			// A user-triggered view broadcast before the next simulation tick
			// must not disclose another frame to the revoked room member.
			s.follow(remaining, pair.pilot.ID, now)
			if _, exists := s.connections[c]; exists || !hasError(c, "room_access_changed") || len(c.updates) != 0 {
				t.Fatal("removed room member retained a view through another spectator")
			}
		})
	}
}

func TestRoomInfinityActiveP2RequiresPrimaryCombatAtomically(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	pair, c, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	pair.pilot.Score, pair.local.Score = 9, 4
	primary, local := pair.seat, pair.localSeat
	primaryID, localID := primary.ID, local.ID
	drain(members[0])
	action(t, s.hub, members[0], map[string]any{"type": "spectate", "spectating": true})
	if !hasError(members[0], "local_requires_primary") || primary.Spectating || local.Spectating || primary.ID != primaryID || local.ID != localID || pair.pilot.client != c || pair.pilot.Score != 9 || pair.local.Score != 4 {
		t.Fatal("primary demotion silently dropped P2 or changed either role/score")
	}
	s.step(now)
	if s.connections[c].pilot != pair.pilot || s.connections[c].local != pair.local || pair.arena.players != 2 || s.privateCount != 2 {
		t.Fatal("rejected primary demotion retired live combat authority")
	}
}

func TestRoomInfinitySetupAndLocalPromotionRejectP2OnlyController(t *testing.T) {
	h, members, room := makeRoom(t, 2)
	rules := room.Game.settings()
	rules.Infinity, rules.TeamMode = true, "ffa"
	action(t, h, members[0], map[string]any{"type": "rules", "rules": rules})
	action(t, h, members[0], map[string]any{"type": "add", "kind": "local", "name": "Wing"})
	local := room.Players[2]
	action(t, h, members[0], map[string]any{"type": "spectate", "spectating": true})
	readyAll(t, h, members[1:])
	drain(members[0])
	action(t, h, members[0], map[string]any{"type": "start"})
	if room.infinityActive || !hasError(members[0], "local_requires_primary") || !members[0].player.Spectating || local.Spectating {
		t.Fatal("private launch silently omitted a spectator-controlled P2")
	}
	action(t, h, members[0], map[string]any{"type": "spectate", "target": local.ID, "member": local.Member, "spectating": true})
	readyAll(t, h, members[1:])
	action(t, h, members[0], map[string]any{"type": "start"})
	if !room.infinityActive {
		t.Fatal("a primary and P2 both spectating blocked another combat controller")
	}
	drain(members[0])
	action(t, h, members[0], map[string]any{"type": "spectate", "target": local.ID, "member": local.Member, "spectating": false})
	if !hasError(members[0], "local_requires_primary") || !local.Spectating || !members[0].player.Spectating {
		t.Fatal("local promotion created an unsupported P2-only controller")
	}
}

func TestRoomInfinityObserverKeepsExistingBotViewActiveWithoutChangingPopulation(t *testing.T) {
	rules := defaultRules()
	rules.Infinity, rules.InfinityRandomBots, rules.TeamMode = true, true, "ffa"
	a := newRoomInfiniteArena(rules, nil)
	now := time.Now()
	human := a.join(fakeClient(), "Human", now)
	fillRoamingBots(a)
	bot := roamingBots(a)[0]
	bot.X, bot.Y = human.X+50*cellSize, human.Y-40*cellSize
	bot.Score = 12
	x, y, life, id, nextID := bot.X, bot.Y, bot.Spawn, bot.ID, a.nextID
	observer := &infiniteObserver{following: bot.ID}
	if !a.addObserver(partySnapshotClient(), observer, 1, false, 0) {
		t.Fatal("could not register the read-only view")
	}
	a.tick = a.nextBot
	a.populate()
	if a.outsideActiveViews(bot) || bot.X != x || bot.Y != y || bot.Spawn != life || a.nextID != nextID || len(roamingBots(a)) != 8 {
		t.Fatal("a currently observed bot was relocated, replaced, or increased the budget")
	}
	human.HP, human.paused = 0, true
	humanLife := human.Spawn
	bot.HP, bot.respawn = 0, a.tick+1
	a.step(now.Add(time.Second))
	if human.HP != 0 || human.Spawn != humanLife || bot.HP != infiniteMaxHP || bot.Spawn != life+1 || bot.ID != id || bot.Score != 12 || a.nextID != nextID || a.roamingBotBudget() != 8 {
		t.Fatal("observer failed to activate the existing bot life or altered the human's paused respawn/count")
	}
	if observer.following != id || math.Hypot(bot.X-x, bot.Y-y) > 6*cellSize {
		t.Fatal("observed respawn jumped back to a distant human instead of its visible region")
	}
	a.suspend(human)
	a.step(now.Add(2 * time.Second))
	if a.connected != 0 || a.roamingBotBudget() != 0 || len(roamingBots(a)) != 0 || a.nextID != nextID {
		t.Fatal("a spectator retained roaming population without a connected human")
	}
}
