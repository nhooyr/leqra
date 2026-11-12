package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func publicStoreFixture(t *testing.T, path string) *infiniteServer {
	t.Helper()
	s := newInfiniteServer(newHub(4))
	if err := s.openPublicStore(path); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.close)
	return s
}
func savedPublicJoin(t *testing.T, s *infiniteServer, msg infiniteMessage) (infiniteConnection, *Client, string) {
	t.Helper()
	conn, c, reject := tryInfinityReconnect(t, s, msg, time.Now())
	if reject != "" {
		t.Fatalf("public join: %s", reject)
	}
	packets := drain(c)
	if len(packets) != 1 || packets[0]["type"] != "welcome" || packets[0]["public"] != true {
		t.Fatalf("welcome: %v", packets)
	}
	token, _ := packets[0]["publicToken"].(string)
	if _, ok := publicTokenHash(token); !ok {
		t.Fatal("public welcome omitted a 256-bit bearer")
	}
	return conn, c, token
}
func commitPublicFixture(t *testing.T, s *infiniteServer) {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.persistPublicLocked(nil, nil); err != nil {
		t.Fatal(err)
	}
}

func TestPublicInfinityDurableIdentityRequiresOwnerProof(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	first, c, token := savedPublicJoin(t, s, infiniteMessage{Name: "SAME", LocalName: "WING"})
	other, _, otherToken := savedPublicJoin(t, s, infiniteMessage{Name: "OTHER"})
	s.public.eliminatePilot(other.pilot, first.pilot.ID, 0, first.pilot.Name)
	first.local.Score = 9
	first.pilot.ColorIndex = 3
	commitPublicFixture(t, s)
	if token == otherToken || first.pilot.ID == other.pilot.ID {
		t.Fatal("same callsigns shared identity")
	}
	id, localID := first.pilot.ID, first.local.ID
	s.remove(c)
	if s.public.players != 1 {
		t.Fatal("archived identity still consumed seats")
	}
	s.close()
	s = publicStoreFixture(t, path)
	if s.public.players != 0 || s.public.connected != 0 {
		t.Fatal("restored leaderboard occupied public seats")
	}
	restored, _, got := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true, Name: "FORGED", LocalName: "FORGED", ColorIndex: new(int)})
	if got != token || restored.pilot.ID != id || restored.local.ID != localID || restored.pilot.Name != "SAME" || restored.local.Name != "WING" || restored.pilot.Score != 1 || restored.local.Score != 9 || restored.pilot.ColorIndex != 3 {
		t.Fatalf("saved identity changed: %+v %+v", restored.pilot, restored.local)
	}
	restoredOther, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: otherToken, Resume: true})
	if restoredOther.pilot.Score != -1 || restoredOther.pilot.ID == id {
		t.Fatal("same-name identity recovered someone else's score")
	}
	if _, _, reject := tryInfinityReconnect(t, s, infiniteMessage{Name: "same"}, time.Now()); !strings.Contains(reject, "unused online callsign") {
		t.Fatal("same callsign recovered identity or escaped ownership")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	wal, _ := os.ReadFile(path + "-wal")
	if bytes.Contains(append(data, wal...), []byte(token)) {
		t.Fatal("raw bearer persisted to SQLite")
	}
}

func TestPublicInfinityBearerHandoverPreservesLiveBody(t *testing.T) {
	s := publicStoreFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	first, old, token := savedPublicJoin(t, s, infiniteMessage{Name: "PILOT"})
	first.pilot.HP = 1
	first.pilot.Score = 8
	first.pilot.kit.Power = "laser"
	first.pilot.kit.PowerTime = 4
	x, y, spawn := first.pilot.X, first.pilot.Y, first.pilot.Spawn
	next, current, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true})
	if next.pilot != first.pilot || next.pilot.HP != 1 || next.pilot.Score != 8 || next.pilot.kit.Power != "laser" || next.pilot.X != x || next.pilot.Y != y || next.pilot.Spawn != spawn {
		t.Fatal("transport handover recreated the tank")
	}
	select {
	case <-old.done:
	case <-time.After(time.Second):
		t.Fatal("old socket survived handover")
	}
	notices := drain(old)
	if len(notices) != 1 || notices[0]["code"] != "session_replaced" {
		t.Fatal("superseded client lacked terminal notice")
	}
	s.disconnect(old, time.Now())
	if s.public.players != 1 || s.public.connected != 1 || next.pilot.client != current {
		t.Fatal("stale disconnect retired replacement")
	}
}

func TestPublicInfinityRejectsForgedIdentityAndIgnoresClientScores(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	victim, _, token := savedPublicJoin(t, s, infiniteMessage{Name: "SAME"})
	victim.pilot.Score = 11
	commitPublicFixture(t, s)
	for restart := 0; restart < 2; restart++ {
		if restart == 1 {
			s.close()
			s = publicStoreFixture(t, path)
		}
		for _, forged := range []string{"p_bad", strings.Repeat("f", 64), "p_" + strings.Repeat("A", 43)} {
			raw := fmt.Sprintf(`{"type":"join","name":"SAME","publicToken":%q,"score":999999,"leaderboard":[{"id":%d,"score":999999}],"rank":1,"id":%d,"token_hash":%q}`, forged, victim.pilot.ID, victim.pilot.ID, token)
			var msg infiniteMessage
			if err := json.Unmarshal([]byte(raw), &msg); err != nil {
				t.Fatal(err)
			}
			if _, _, reject := tryInfinityReconnect(t, s, msg, time.Now()); reject != infinitePublicResumeInvalid {
				t.Fatalf("forged bearer accepted: %q", reject)
			}
		}
		var msg infiniteMessage
		raw := fmt.Sprintf(`{"type":"join","name":"ATTACK%d","score":999999,"leaderboard":[{"id":%d,"score":999999}],"rank":1,"id":%d}`, restart, victim.pilot.ID, victim.pilot.ID)
		if err := json.Unmarshal([]byte(raw), &msg); err != nil {
			t.Fatal(err)
		}
		fresh, c, _ := savedPublicJoin(t, s, msg)
		if fresh.pilot.Score != 0 || fresh.pilot.ID == victim.pilot.ID {
			t.Fatal("join trusted client score or ID")
		}
		s.remove(c)
		raw = fmt.Sprintf(`{"type":"join","publicToken":%q,"resume":true,"name":"FORGED","score":999999,"leaderboard":[{"score":999999}],"rank":1,"id":%d,"token_hash":"forged"}`, token, fresh.pilot.ID)
		if err := json.Unmarshal([]byte(raw), &msg); err != nil {
			t.Fatal(err)
		}
		restored, _, _ := savedPublicJoin(t, s, msg)
		if restored.pilot.Score != 11 || restored.pilot.ID != victim.pilot.ID || restored.pilot.Name != "SAME" {
			t.Fatal("forged resume payload mutated saved score, name, or identity")
		}
	}
}

func TestPublicInfinitySocketInputCannotWriteScore(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	token := ""
	for restart := 0; restart < 2; restart++ {
		app := newApp(4, nil)
		t.Cleanup(app.infinite.close)
		if err := app.infinite.openPublicStore(path); err != nil {
			t.Fatal(err)
		}
		server := httptest.NewServer(app.handler())
		t.Cleanup(server.Close)
		join := map[string]string{"type": "join", "version": version, "name": "PILOT", "score": "999999", "id": "1234", "rank": "1", "leaderboard": "forged"}
		if token != "" {
			join["publicToken"] = token
		}
		c, r := dialInfinite(t, server.URL, join, false)
		var welcome map[string]any
		readInfinitePacket(t, r, &welcome)
		if welcome["type"] != "welcome" {
			t.Fatal(welcome)
		}
		token, _ = welcome["publicToken"].(string)
		payload := []byte(`{"type":"input","seq":1,"score":999999,"id":1234,"rank":1,"publicToken":"p_forged","leaderboard":[{"score":999999}],"forward":true}`)
		if _, err := c.Write(maskedFrame(1, true, payload)); err != nil {
			t.Fatal(err)
		}
		if _, err := c.Write(maskedFrame(1, true, []byte(`{"type":"ping","t":1}`))); err != nil {
			t.Fatal(err)
		}
		var pong map[string]any
		readInfinitePacket(t, r, &pong)
		if pong["type"] != "pong" {
			t.Fatal(pong)
		}
		app.infinite.public.mu.Lock()
		p := app.infinite.public.pilots[0]
		score, accepted := p.Score, p.input.Forward
		app.infinite.public.mu.Unlock()
		if score != 0 || !accepted {
			t.Fatal("input forged score or failed authenticated controls")
		}
		commitPublicFixture(t, app.infinite)
		_ = c.Close()
		server.Close()
		app.infinite.close()
	}
}

func TestPublicInfinityCrashWriter(t *testing.T) {
	path := os.Getenv("LEQRA_TEST_CRASH_DB")
	if path == "" {
		return
	}
	s := newInfiniteServer(newHub(4))
	if err := s.openPublicStore(path); err != nil {
		t.Fatal(err)
	}
	first, _, token := savedPublicJoin(t, s, infiniteMessage{Name: "SAME"})
	second, _, _ := savedPublicJoin(t, s, infiniteMessage{Name: "OTHER"})
	s.public.eliminatePilot(second.pilot, first.pilot.ID, 0, first.pilot.Name)
	bot := s.public.addPilot("BOT 1", true, 0, 0, 1, 3)
	bot.Score = 7
	bot.ambientNumber = 1
	commitPublicFixture(t, s)
	ready, _ := json.Marshal(map[string]any{"token": token, "id": first.pilot.ID, "bot": bot.ID})
	fmt.Println(string(ready))
	time.Sleep(time.Minute)
}

func TestPublicInfinityWALSurvivesSIGKILL(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestPublicInfinityCrashWriter$")
	cmd.Env = append(os.Environ(), "LEQRA_TEST_CRASH_DB="+path)
	output, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	line, err := bufio.NewReader(output).ReadBytes('\n')
	if err != nil {
		t.Fatalf("crash writer: %v %s", err, stderr.String())
	}
	var ready struct {
		Token   string
		ID, Bot int
	}
	if err = json.Unmarshal(line, &ready); err != nil {
		t.Fatalf("crash writer handshake: %s", line)
	}
	if info, err := os.Stat(path + "-wal"); err != nil || info.Size() == 0 {
		t.Fatal("test did not leave committed WAL data")
	}
	if err = cmd.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = cmd.Wait()
	s := publicStoreFixture(t, path)
	if s.public.players != 0 {
		t.Fatal("crash restore consumed seats")
	}
	entries := s.AdminLeaderboard()
	if len(entries) != 3 || entries[0].ID != ready.Bot || entries[0].Score != 7 {
		t.Fatalf("WAL lost ranked humans or bot: %+v", entries)
	}
	p, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: ready.Token, Resume: true})
	if p.pilot.ID != ready.ID || p.pilot.Score != 1 {
		t.Fatal("SIGKILL lost committed score")
	}
	if len(s.public.inactiveBots) != 1 || s.public.inactiveBots[0].ID != ready.Bot {
		t.Fatal("roaming bot identity was not restored")
	}
}

func TestPublicInfinityRejectsCorruptDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	if err := os.WriteFile(path, []byte("not a database"), 0600); err != nil {
		t.Fatal(err)
	}
	s := newInfiniteServer(newHub(4))
	if err := s.openPublicStore(path); err == nil {
		t.Fatal("corrupt saved scores silently reset")
	}
}

func TestPublicInfinityAdminResetKeepsActiveProofAndDeletesOffline(t *testing.T) {
	s := publicStoreFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	active, c, token := savedPublicJoin(t, s, infiniteMessage{Name: "ACTIVE", LocalName: "WING"})
	offline, off, offToken := savedPublicJoin(t, s, infiniteMessage{Name: "OFFLINE"})
	active.pilot.Score = 5
	active.local.Score = 4
	offline.pilot.Score = 9
	commitPublicFixture(t, s)
	s.remove(off)
	if n, err := s.RemovePublicLeaderboard("^WING$"); err != nil || n != 1 {
		t.Fatalf("selected removal: %d %v", n, err)
	}
	if active.pilot.Score != 5 || active.local.Score != 0 {
		t.Fatal("selected removal touched unrelated pilot")
	}
	if n, err := s.ResetPublicLeaderboard(); err != nil || n != 3 {
		t.Fatalf("reset: %d %v", n, err)
	}
	if active.pilot.Score != 0 || s.public.players != 2 || len(s.AdminLeaderboard()) != 2 {
		t.Fatal("reset removed connected bodies or retained offline rows")
	}
	if !receivedType(c, "leaderboard_reset") {
		t.Fatal("reset notice omitted")
	}
	fresh, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: offToken, Resume: true, Name: "OFFLINE"})
	if fresh.pilot.Score != 0 || fresh.pilot.ID == offline.pilot.ID {
		t.Fatal("full reset retained offline score identity or lost name owner")
	}
	s.remove(fresh.pilot.client)
	restored, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true})
	if restored.pilot != active.pilot || restored.pilot.Score != 0 {
		t.Fatal("reset invalidated connected bearer")
	}
	s.close()
	if _, err := s.ResetPublicLeaderboard(); err == nil {
		t.Fatal("closed server accepted administration")
	}
}

func TestPublicInfinityArchiveRanksUseBoundedCandidates(t *testing.T) {
	a := newSeededInfiniteArena(1)
	a.publicEntries = make(map[int]infinitePublicEntry)
	for id := 1; id <= 100000; id++ {
		a.publicEntries[id] = infinitePublicEntry{infiniteLeader: infiniteLeader{ID: id, Name: "SAVED", Score: id}, listed: true}
	}
	a.nextID = 100000
	p := a.join(fakeClient(), "LIVE", time.Now())
	p.Score = 50000
	a.publicArchiveDirty = true
	leaders := a.rankedLeaders(nil)
	if len(leaders) > infiniteLeaderCount+len(a.pilots) || leaders[0].ID != 100000 || a.publicRank(p) != 50002 {
		t.Fatalf("archive ranks or candidate bound: %d rank%d", len(leaders), a.publicRank(p))
	}
	backing := &a.publicArchive[0]
	a.rankedLeaders(leaders)
	if &a.publicArchive[0] != backing {
		t.Fatal("unchanged archive rebuilt on display tick")
	}
}

func BenchmarkPublicInfinityCommittedScore(b *testing.B) {
	s := newInfiniteServer(newHub(4))
	if err := s.openPublicStore(filepath.Join(b.TempDir(), "data.sqlite")); err != nil {
		b.Fatal(err)
	}
	defer s.close()
	c := fakeClient()
	s.admit(c)
	conn, reject := s.join(c, infiniteMessage{Name: "BENCH"}, time.Now())
	if reject != "" {
		b.Fatal(reject)
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		s.mu.Lock()
		conn.pilot.Score++
		if err := s.persistPublicLocked(nil, nil); err != nil {
			b.Fatal(err)
		}
		s.mu.Unlock()
	}
}

func TestPublicInfinityZeroScorePruningKeepsNamesAndMeaningfulScores(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	zero, c, token := savedPublicJoin(t, s, infiniteMessage{Name: "Zero"})
	s.remove(c)
	meaningful, other, _ := savedPublicJoin(t, s, infiniteMessage{Name: "Saved"})
	meaningful.pilot.Score = -7
	commitPublicFixture(t, s)
	s.remove(other)
	hash, _ := publicTokenHash(token)
	profile := s.publicProfiles[hash]
	profile.used = time.Now().Add(-40 * 24 * time.Hour).Unix()
	s.publicProfiles[hash] = profile
	// Fill the in-memory zero churn index without thousands of fsyncs. These
	// synthetic groups are never exposed as authenticated client identities.
	for i := 0; i < infiniteZeroProfiles; i++ {
		id := 100000 + i
		key := fmt.Sprintf("%064x", i)
		s.publicProfiles[key] = infinitePublicProfile{hash: key, primary: id, used: time.Now().Unix()}
		s.publicZeroProfiles[key] = true
		s.public.publicEntries[id] = infinitePublicEntry{infiniteLeader: infiniteLeader{ID: id, Name: "CHURN"}, listed: true}
	}
	reserved := infiniteRoomPilot{room: infiniteRoom{room: &Room{}, generation: 1}, seat: &Player{}}
	s.reservations[reserved] = infiniteReservation{connection: zero, until: time.Now().Add(time.Second)}
	s.mu.Lock()
	err := s.prunePublicProfiles(time.Now())
	s.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := s.publicProfiles[hash]; !ok {
		t.Fatal("reserved public identity was pruned")
	}
	delete(s.reservations, reserved)
	s.mu.Lock()
	err = s.prunePublicProfiles(time.Now())
	s.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := s.publicProfiles[hash]; ok {
		t.Fatal("old zero-score profile survived churn cap")
	}
	if _, ok := s.public.publicEntries[zero.pilot.ID]; ok {
		t.Fatal("pruned zero profile retained its score row")
	}
	if s.public.publicEntries[meaningful.pilot.ID].Score != -7 {
		t.Fatal("meaningful negative score expired")
	}
	s.close()
	s = publicStoreFixture(t, path)
	if got := s.hub.callsigns.availability("", []string{"zero", "saved"}); got[0].Available || got[1].Available {
		t.Fatal("score pruning released online names")
	}
	restored, _, same := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true, Name: "Zero"})
	if same != token || restored.pilot.Score != 0 {
		t.Fatal("pruned owner could not return to its claimed name")
	}
}

func TestPublicInfinityStatusWithholdsUncommittedScore(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	if err := app.infinite.openPublicStore(filepath.Join(t.TempDir(), "data.sqlite")); err != nil {
		t.Fatal(err)
	}
	p, _, _ := savedPublicJoin(t, app.infinite, infiniteMessage{Name: "Committed"})
	p.pilot.Score = 9
	// Force the durable transaction to fail after the simulated score change.
	if err := app.infinite.publicDB.Close(); err != nil {
		t.Fatal(err)
	}
	app.infinite.step(time.Now())
	app.infinite.step(time.Now())
	response := httptest.NewRecorder()
	app.infinityStatus(response, httptest.NewRequest("GET", "/api/infinity", nil))
	var status struct{ Leaders []infiniteStatusLeader }
	if err := json.Unmarshal(response.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	for _, leader := range status.Leaders {
		if leader.Score != 0 {
			t.Fatal("uncommitted score escaped status endpoint")
		}
	}
	if !app.infinite.public.broadcastPending {
		t.Fatal("failed score commit did not retain pending broadcast")
	}
	// Permit in-memory cleanup after deliberately closing the test database.
	app.infinite.publicDB = nil
}

func TestPublicInfinityRoomPartyScoreSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	h := s.hub
	c := fakeClient()
	h.addClient(c)
	action(t, h, c, map[string]any{"type": "create", "name": "Party Lead"})
	action(t, h, c, map[string]any{"type": "add", "kind": "local", "name": "Party Wing"})
	action(t, h, c, map[string]any{"type": "select_public_infinity", "enabled": true})
	launchPublicParty(t, s, c, time.Now())
	room := c.room
	pair, _, token := savedPublicJoin(t, s, infiniteMessage{Code: room.Code, Token: c.player.Token, PublicToken: c.player.PublicToken})
	if pair.local == nil || token != c.player.PublicToken {
		t.Fatal("room party lost local seat or durable owner proof")
	}
	pair.pilot.Score = 17
	pair.local.Score = -2
	commitPublicFixture(t, s)
	id, local := pair.pilot.ID, pair.local.ID
	s.close()
	s = publicStoreFixture(t, path)
	returned, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true})
	if returned.pilot.ID != id || returned.local.ID != local || returned.pilot.Score != 17 || returned.local.Score != -2 {
		t.Fatal("room party lost score across restart")
	}
}

func TestPublicInfinityManualNamesPreserveScoresAndP2Selection(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	first, _, token := savedPublicJoin(t, s, infiniteMessage{Name: "Original", LocalName: "Wing"})
	savedPublicJoin(t, s, infiniteMessage{Name: "Taken"})
	first.pilot.Score = 7
	first.local.Score = 3
	commitPublicFixture(t, s)
	id, localID := first.pilot.ID, first.local.ID
	if _, _, reject := tryInfinityReconnect(t, s, infiniteMessage{PublicToken: token, UpdateNames: true, Name: "taken", LocalName: "Not Claimed"}, time.Now()); !strings.Contains(reject, "unused online callsign") {
		t.Fatal("manual Play silently ignored conflicting callsign")
	}
	if first.pilot.Name != "Original" || !s.hub.callsigns.availability("", []string{"Not Claimed"})[0].Available {
		t.Fatal("failed manual rename partially consumed batch")
	}
	renamed, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, UpdateNames: true, Name: "Renamed", LocalName: "New Wing"})
	if renamed.pilot != first.pilot || renamed.pilot.ID != id || renamed.local.ID != localID || renamed.pilot.Name != "Renamed" || renamed.local.Name != "New Wing" || renamed.pilot.Score != 7 || renamed.local.Score != 3 {
		t.Fatal("manual name update changed authoritative score identity")
	}
	solo, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, UpdateNames: true, Name: "Renamed"})
	if solo.local != nil || s.publicProfiles[solo.pilot.publicKey].localEnabled || s.public.publicEntries[localID].Score != 3 {
		t.Fatal("manual P2 removal discarded saved score or stayed enabled")
	}
	s.close()
	s = publicStoreFixture(t, path)
	recovered, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true, Name: "FORGED", LocalName: "FORGED"})
	if recovered.local != nil || recovered.pilot.Name != "Renamed" || recovered.pilot.Score != 7 {
		t.Fatal("cold recovery restored removed P2 or trusted draft names")
	}
	pair, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, UpdateNames: true, Name: "Renamed", LocalName: "New Wing"})
	if pair.local == nil || pair.local.ID != localID || pair.local.Score != 3 || pair.pilot.ID != id {
		t.Fatal("deliberate P2 selection lost archived owned score")
	}
}

func TestPublicInfinitySupersededTransportReceivesTerminalNotice(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	_, old := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": "Session"}, false)
	var welcome map[string]any
	readInfinitePacket(t, old, &welcome)
	token, _ := welcome["publicToken"].(string)
	_, current := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "publicToken": token}, false)
	var next map[string]any
	readInfinitePacket(t, current, &next)
	if next["type"] != "welcome" || next["id"] != welcome["id"] {
		t.Fatal("valid replacement failed")
	}
	var terminal map[string]any
	readInfinitePacket(t, old, &terminal)
	if terminal["type"] != "error" || terminal["code"] != "session_replaced" {
		t.Fatal("superseded transport cannot stop retrying")
	}
	if app.infinite.notifyShutdown() != 1 {
		t.Fatal("shutdown attempted to notify replaced transport")
	}
	var shutdown map[string]any
	readInfinitePacket(t, current, &shutdown)
	if shutdown["code"] != "server_shutdown" {
		t.Fatal("shutdown lacked retriable terminal code")
	}
}

func TestInfinityWelcomeDistinguishesOwnerProofFromPublicRoute(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 1, false)
	_, c, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: clients[0].player.Token, PublicToken: clients[0].player.PublicToken}, time.Now())
	if reject != "" {
		t.Fatal(reject)
	}
	packets := drain(c)
	if len(packets) != 1 || packets[0]["type"] != "welcome" || packets[0]["public"] == true || packets[0]["publicToken"] == nil || packets[0]["generation"] == nil {
		t.Fatal("private owner proof changed route or dropped private generation")
	}
	savedPublicJoin(t, s, infiniteMessage{Name: "Public Route"})
}
