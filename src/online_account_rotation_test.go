package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func freshAccountKey(t *testing.T) string {
	t.Helper()
	token, _, err := newPublicToken()
	if err != nil {
		t.Fatal(err)
	}
	return token
}

func TestOnlineAccountRotationPreservesScoresAliasesAndRevocationAcrossRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	pair, old, token := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Wing"})
	primaryID, localID := pair.pilot.ID, pair.local.ID
	pair.pilot.Score, pair.local.Score = 31, -7
	if _, err := a.hub.callsigns.claim(token, []string{"Old Alias"}); err != nil {
		t.Fatal(err)
	}
	commitPublicFixture(t, a.infinite)
	candidate := freshAccountKey(t)
	response := accountRequest(a, "/api/account/rotate", fmt.Sprintf(`{"publicToken":%q,"newPublicToken":%q}`, token, candidate))
	var rotation onlineAccountRotation
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &rotation) != nil || rotation.PublicToken != candidate {
		t.Fatalf("rotation failed: %d %s", response.Code, response.Body.String())
	}
	if rotation.PublicProfile == nil || rotation.PublicProfile.Score != 31 || rotation.PublicProfile.LocalScore == nil || *rotation.PublicProfile.LocalScore != -7 || rotation.TotalNames != 3 {
		t.Fatal("rotation changed authoritative score or aliases")
	}
	if _, err := a.infinite.accountInfo(token); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("old account key remains valid")
	}
	notices := drain(old)
	if len(notices) != 1 || notices[0]["code"] != "account_key_revoked" || strings.Contains(fmt.Sprint(notices), candidate) {
		t.Fatal("old device lacked terminal revocation or received the new key")
	}
	if pair.pilot.client != nil || a.infinite.public.players != 0 || len(a.infinite.connections) != 0 {
		t.Fatal("rotation retained old body authority")
	}
	pair.arena.setConnectionInput(old, pair.pilot, pair.pilot, Input{Seq: 999, Fire: true, Forward: true}, false, time.Now())
	if pair.pilot.input.Fire || pair.pilot.input.Forward {
		t.Fatal("already-read old input survived revocation")
	}
	a.infinite.renamePilot(old, infiniteMessage{Name: "Hacked", RequestID: 1}, time.Now())
	if pair.pilot.Name != "Primary" || !a.hub.callsigns.availability("", []string{"Hacked"})[0].Available {
		t.Fatal("revoked transport could rename or claim an alias")
	}
	if _, _, reject := tryInfinityReconnect(t, a.infinite, infiniteMessage{PublicToken: token, Resume: true}, time.Now()); reject != infiniteAccountKeyRevoked {
		t.Fatalf("old public key fell back to new identity: %q", reject)
	}
	// Simulate a lost rotation HTTP response. Validating the pre-saved candidate
	// recovers the same owner without repeating or rolling back the operation.
	info, err := a.infinite.accountInfo(candidate)
	if err != nil || info.PublicProfile.Name != "Primary" || info.PublicProfile.Score != 31 {
		t.Fatal("saved candidate could not recover an ambiguous rotation")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if _, err := a.infinite.accountInfo(token); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("restart forgot revoked account key")
	}
	restored, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: candidate, Resume: true})
	if restored.pilot.ID != primaryID || restored.local.ID != localID || restored.pilot.Score != 31 || restored.local.Score != -7 {
		t.Fatal("restart changed rotated account score identities")
	}
	if _, err := a.hub.callsigns.claim("", []string{"Old Alias"}); err == nil {
		t.Fatal("rotation released permanent aliases")
	}
	if _, err := a.hub.callsigns.claim(token, []string{"Unused"}); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("revoked key created fresh claims")
	}
	if _, err := a.hub.callsigns.claim(candidate, []string{"Old Alias"}); err != nil {
		t.Fatal("new key lost historical alias ownership")
	}
}

func TestOnlineAccountRotationRevokesPrivateRoomsTokensAndReservations(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	_, _, token := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Public"})
	h := a.hub
	roomClient := fakeClient()
	h.addClient(roomClient)
	action(t, h, roomClient, map[string]any{"type": "create", "name": "Private", "publicToken": token})
	action(t, h, roomClient, map[string]any{"type": "add", "kind": "local", "name": "Private Wing"})
	room, member, roomToken := roomClient.room, roomClient.player, roomClient.player.Token
	room.Game.Rules.Infinity = true
	action(t, h, roomClient, map[string]any{"type": "start"})
	join := infiniteMessage{Code: room.Code, Token: roomToken}
	connection, arenaClient, reject := tryInfinityReconnect(t, a.infinite, join, time.Now())
	if reject != "" || connection.local == nil {
		t.Fatal("private pair fixture failed", reject)
	}
	drain(roomClient)
	drain(arenaClient)
	connection.arena.setConnectionInput(arenaClient, connection.pilot, connection.local, Input{Seq: 1, Fire: true}, false, time.Now())
	a.infinite.disconnect(arenaClient, time.Now())
	if len(a.infinite.reservations) != 1 {
		t.Fatal("private pair was not reserved")
	}
	candidate := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(token, candidate); err != nil {
		t.Fatal(err)
	}
	if len(a.infinite.reservations) != 0 || a.infinite.privateCount != 0 || room.contains(member) || roomClient.room != nil || roomClient.player != nil || member.Token != "" || member.PublicToken != "" || !roomClient.accountRevoked {
		t.Fatal("private room authority survived account-key reset")
	}
	if !hasError(roomClient, "account_key_revoked") {
		t.Fatal("private device received no explicit reset notice")
	}
	newClient := fakeClient()
	action(t, h, newClient, map[string]any{"type": "join", "code": room.Code, "token": roomToken, "name": "Private"})
	if newClient.player != nil || !hasError(newClient, "account_key_revoked") {
		t.Fatal("old private room token could resume or obtain new owner key")
	}
	roomClient.msgWindow = time.Time{}
	action(t, h, roomClient, map[string]any{"type": "create", "name": "New Account"})
	if roomClient.player != nil || !hasError(roomClient, "account_key_revoked") {
		t.Fatal("already-read old room action escaped terminal revocation")
	}
	join.Resume, join.Generation = true, room.infinityGeneration
	if _, _, rejected := tryInfinityReconnect(t, a.infinite, join, time.Now()); rejected == "" {
		t.Fatal("old private Infinity route survived reset")
	}
}

func TestOnlineAccountRotationFailureRollsBackWithoutDisconnecting(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, active, token := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Owner"})
	pair.pilot.Score = 9
	commitPublicFixture(t, a.infinite)
	if _, err := a.infinite.publicDB.Exec(`CREATE TRIGGER fail_account_rotation BEFORE DELETE ON online_owners BEGIN SELECT RAISE(ABORT,'test rotation failure'); END`); err != nil {
		t.Fatal(err)
	}
	candidate := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(token, candidate); err == nil {
		t.Fatal("failed database rotation reported success")
	}
	info, err := a.infinite.accountInfo(token)
	if err != nil || info.PublicProfile.Score != 9 || pair.pilot.client != active || a.infinite.public.players != 1 || len(drain(active)) != 0 {
		t.Fatal("database failure changed owner, score, or live transport")
	}
	if _, err := a.infinite.accountInfo(candidate); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("rolled-back candidate became a valid owner")
	}
	oldHash, _ := publicTokenHash(token)
	var stored string
	if err := a.infinite.publicDB.QueryRow("SELECT owner_hash FROM online_callsigns WHERE canonical_name=?", canonicalCallsign("Owner")).Scan(&stored); err != nil || stored != oldHash {
		t.Fatal("database rollback lost callsign ownership")
	}
}

func TestOnlineAccountRotationRejectsMalformedForgedOrExistingCandidateRequests(t *testing.T) {
	a := accountAppFixture(t, "")
	token, _ := a.hub.callsigns.claim("", []string{"Owner"})
	other, _ := a.hub.callsigns.claim("", []string{"Other"})
	for _, candidate := range []string{"", "p_bad", token, other} {
		if _, err := a.infinite.rotateAccount(token, candidate); !errors.Is(err, errNewAccountKeyInvalid) {
			t.Fatal("invalid or colliding candidate accepted")
		}
	}
	unknown := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(unknown, freshAccountKey(t)); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("unknown old key rotated another owner")
	}
	w := accountRequest(a, "/api/account/rotate", fmt.Sprintf(`{"publicToken":%q,"newPublicToken":%q,"score":999999}`, token, freshAccountKey(t)))
	if w.Code != 400 || len(a.hub.callsigns.owners) != 2 || len(a.hub.callsigns.revoked) != 0 {
		t.Fatal("rotation accepted client-controlled score or changed rejected ownership")
	}
}

func TestOnlineAccountRotationSocketReceivesRevocationAndCannotUseOldKey(t *testing.T) {
	a := accountAppFixture(t, "")
	server := httptest.NewServer(a.handler())
	t.Cleanup(server.Close)
	old, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": "Device"}, false)
	var welcome map[string]any
	readInfinitePacket(t, reader, &welcome)
	token := welcome["publicToken"].(string)
	candidate := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(token, candidate); err != nil {
		t.Fatal(err)
	}
	var notice map[string]any
	readInfinitePacket(t, reader, &notice)
	if notice["code"] != "account_key_revoked" || strings.Contains(fmt.Sprint(notice), candidate) {
		t.Fatal("old transport did not receive safe terminal revocation")
	}
	_ = old.Close()
	_, rejected := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "publicToken": token}, false)
	var denial map[string]any
	readInfinitePacket(t, rejected, &denial)
	if denial["code"] != "account_key_revoked" {
		t.Fatal("offline old device received no explicit key-reset error")
	}
	_, current := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "publicToken": candidate}, false)
	var resumed map[string]any
	readInfinitePacket(t, current, &resumed)
	if resumed["type"] != "welcome" || resumed["id"] != welcome["id"] {
		t.Fatal("new device lost authoritative score identity")
	}
}

func TestOnlineAccountRotationImmediatelyRevokesActivePrivateArenaInput(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 1, true)
	t.Cleanup(s.close)
	token := clients[0].player.PublicToken
	pair, arenaClient, reject := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: clients[0].player.Token}, time.Now())
	if reject != "" {
		t.Fatal(reject)
	}
	drain(arenaClient)
	drain(clients[0])
	pair.arena.setConnectionInput(arenaClient, pair.pilot, pair.pilot, Input{Seq: 1, Fire: true, Forward: true}, false, time.Now())
	pair.arena.setConnectionInput(arenaClient, pair.pilot, pair.local, Input{Seq: 1, Fire: true}, false, time.Now())
	if _, err := s.rotateAccount(token, freshAccountKey(t)); err != nil {
		t.Fatal(err)
	}
	if s.privateCount != 0 || len(s.connections) != 0 || pair.pilot.client != nil || pair.pilot.input.Fire || pair.local.input.Fire || pair.pilot.firePending || pair.local.firePending {
		t.Fatal("active private arena retained control or pending firing")
	}
	pair.arena.setConnectionInput(arenaClient, pair.pilot, pair.local, Input{Seq: 999, Fire: true}, false, time.Now())
	if pair.local.input.Fire || pair.local.firePending || !hasError(arenaClient, "account_key_revoked") || !hasError(clients[0], "account_key_revoked") {
		t.Fatal("old copied arena controller regained authority or missed reset error")
	}
}

func TestOnlineAccountConcurrentRotationHasOneDurableWinner(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	token, err := a.hub.callsigns.claim("", []string{"Owner"})
	if err != nil {
		t.Fatal(err)
	}
	candidates := []string{freshAccountKey(t), freshAccountKey(t)}
	var wg sync.WaitGroup
	start, results := make(chan struct{}), make(chan error, 2)
	for _, candidate := range candidates {
		wg.Add(1)
		go func(candidate string) {
			defer wg.Done()
			<-start
			_, err := a.infinite.rotateAccount(token, candidate)
			results <- err
		}(candidate)
	}
	close(start)
	wg.Wait()
	close(results)
	wins := 0
	for err := range results {
		if err == nil {
			wins++
		} else if !errors.Is(err, errOnlineOwnerRevoked) {
			t.Fatal(err)
		}
	}
	valid := 0
	for _, candidate := range candidates {
		if _, err := a.infinite.accountInfo(candidate); err == nil {
			valid++
		}
	}
	if wins != 1 || valid != 1 || len(a.hub.callsigns.owners) != 1 || len(a.hub.callsigns.revoked) != 1 {
		t.Fatal("concurrent reset created multiple owners or lost all replacement keys")
	}
}
