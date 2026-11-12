package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func independentPair(t *testing.T, s *infiniteServer, primary, local, token string) (infiniteConnection, *Client, string, string) {
	t.Helper()
	key := freshAccountKey(t)
	pair, c, owner := savedPublicJoin(t, s, infiniteMessage{Name: primary, LocalName: local, PublicToken: token, LocalPublicToken: key, LocalNewAccount: true, IndependentAccounts: true, UpdateNames: true})
	if pair.local == nil || pair.local.publicToken != key || pair.pilot.publicToken == key {
		t.Fatal("P2 did not receive an independent durable credential")
	}
	return pair, c, owner, key
}

func TestIndependentSeatClaimsValidateAtomically(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	r := a.hub.callsigns
	first, _ := r.claim("", []string{"First"})
	_, _ = r.claim("", []string{"Taken"})
	candidate := freshAccountKey(t)
	for _, requests := range [][]accountSeatClaim{
		{{token: first, name: "Unclaimed"}, {token: candidate, name: "Taken", newAccount: true, transferFrom: first}},
		{{token: first, name: "Unclaimed"}, {token: candidate, name: "Second"}},
		{{token: first, name: "Unclaimed"}, {token: first, name: "Second"}},
		{{token: first, name: "Unclaimed"}, {name: "Second", newAccount: true}},
	} {
		if _, err := r.claimSeatAccounts(requests, nil); err == nil {
			t.Fatal("invalid P2 identity accepted")
		}
		if len(r.owners) != 2 || !r.availability("", []string{"Unclaimed"})[0].Available || len(r.seatMigrations) != 0 {
			t.Fatal("failed pair admission partially allocated an owner, alias, or migration")
		}
	}
	if _, err := r.db.Exec(`CREATE TRIGGER fail_seat_claim BEFORE INSERT ON online_seat_migrations BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	if _, err := r.claimSeatAccounts([]accountSeatClaim{{token: first, name: "Unclaimed"}, {token: candidate, name: "Second", newAccount: true, transferFrom: first}}, nil); err == nil || len(r.owners) != 2 || !r.availability("", []string{"Second", "Unclaimed"})[0].Available {
		t.Fatal("database failure partially committed paired ownership")
	}
}

func TestIndependentPendingSplitUniquenessMatchesSQLite(t *testing.T) {
	for _, sqlite := range []bool{false, true} {
		t.Run(fmt.Sprint(sqlite), func(t *testing.T) {
			path := ""
			if sqlite {
				path = filepath.Join(t.TempDir(), "data.sqlite")
			}
			a := accountAppFixture(t, path)
			r := a.hub.callsigns
			primary, _ := r.claim("", []string{"Primary", "Wing"})
			first, second := freshAccountKey(t), freshAccountKey(t)
			if _, err := r.claimSeatAccounts([]accountSeatClaim{{token: primary, name: "Primary"}, {token: first, name: "Wing", newAccount: true, transferFrom: primary}}, nil); err != nil {
				t.Fatal(err)
			}
			requests := []accountSeatClaim{{token: primary, name: "New Primary"}, {token: second, name: "New Wing", newAccount: true, transferFrom: primary}}
			if _, err := r.claimSeatAccounts(requests, nil); !errors.Is(err, errSeatMigrationPending) {
				t.Fatal("second pending candidate was not rejected", err)
			}
			if len(r.owners) != 2 || len(r.seatMigrations) != 1 || !r.availability("", []string{"New Primary"})[0].Available || !r.availability("", []string{"New Wing"})[0].Available {
				t.Fatal("rejected pending split partially allocated an owner or alias")
			}
			a.infinite.mu.Lock()
			err := a.infinite.applySeatMigrations()
			a.infinite.mu.Unlock()
			if err != nil {
				t.Fatal(err)
			}
			if _, err := r.claimSeatAccounts(requests, nil); err != nil {
				t.Fatal("completed migration blocked a later fresh account", err)
			}
		})
	}
}

func TestIndependentPublicP2CanBecomeP1WithoutChangingItsIdentity(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	pair, old, primary, local := independentPair(t, a.infinite, "Primary", "Wing", "")
	primaryID, localID := pair.pilot.ID, pair.local.ID
	pair.pilot.Score, pair.local.Score = 17, 29
	pair.local.kit.Power, pair.local.kit.PowerTime = "laser", 3
	pair.local.HP = 1
	commitPublicFixture(t, a.infinite)
	a.infinite.renamePilot(old, infiniteMessage{Seat: 1, Name: "New Wing", RequestID: 1}, time.Now())
	if pair.local.Name != "New Wing" {
		t.Fatal("independent P2 could not rename its own callsign", drain(old))
	}
	drain(old)
	a.infinite.renamePilot(old, infiniteMessage{Seat: 0, Name: "New Primary", RequestID: 2}, time.Now())
	if pair.pilot.Name != "New Primary" {
		t.Fatal("P1 rename tried to claim P2's callsign")
	}
	drain(old)
	for _, identity := range []struct {
		key, name string
		score     int
	}{{primary, "New Primary", 17}, {local, "New Wing", 29}} {
		info, err := a.infinite.accountInfo(identity.key)
		if err != nil || info.PublicProfile == nil || info.PublicProfile.Name != identity.name || info.PublicProfile.Score != identity.score || info.PublicProfile.LocalScore != nil || info.TotalNames != 2 {
			t.Fatalf("account exposed another seat's profile or aliases: %+v %v", info, err)
		}
	}
	// Even clients using the old single-account protocol cannot duplicate a live
	// P2 body by presenting its credential as their primary account.
	next, current, got := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: local, Resume: true})
	if got != local || next.pilot != pair.local || next.pilot.ID != localID || next.pilot.Score != 29 || next.pilot.HP != 1 || next.pilot.kit.Power != "laser" || next.local != nil || a.infinite.public.players != 1 {
		t.Fatal("moving P2 to P1 recreated or duplicated the authoritative tank")
	}
	notices := drain(old)
	if len(notices) != 1 || notices[0]["code"] != "session_replaced" || notices[0]["seat"] != float64(1) {
		t.Fatal("paired old device lacked an explicit P2 takeover notice", notices)
	}
	pair.arena.setConnectionInput(old, pair.pilot, pair.local, Input{Seq: 99, Fire: true, Forward: true}, false, time.Now())
	if pair.local.input.Fire || pair.local.input.Forward || pair.local.client != current {
		t.Fatal("old paired transport retained authority after P2 takeover")
	}
	a.infinite.disconnect(old, time.Now())
	if next.pilot.client != current || a.infinite.public.players != 1 {
		t.Fatal("stale paired disconnect retired replacement")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	restored, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: primary, IndependentAccounts: true})
	if restored.pilot.ID != primaryID || restored.pilot.Score != 17 || restored.local != nil {
		t.Fatal("P2 takeover changed P1 identity or score across restart")
	}
	restored, _, _ = savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: local, IndependentAccounts: true})
	if restored.pilot.ID != localID || restored.pilot.Score != 29 {
		t.Fatal("independent P2 score did not survive restart")
	}
}

func TestIndependentP2RotationPreservesP1AndRemovesPrivateDelegation(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, active, primary, local := independentPair(t, a.infinite, "Primary", "Wing", "")
	pair.pilot.Score, pair.local.Score = 8, 13
	commitPublicFixture(t, a.infinite)
	c := fakeClient()
	a.hub.addClient(c)
	action(t, a.hub, c, map[string]any{"type": "create", "name": "Primary", "publicToken": primary, "independentAccounts": true})
	action(t, a.hub, c, map[string]any{"type": "add", "kind": "local", "name": "Wing", "localPublicToken": local, "independentAccounts": true})
	r, p, roomToken := c.room, c.player, c.player.Token
	child := roomLocalController(r, p)
	if child == nil || child.PublicToken != local {
		t.Fatal("private P2 did not use its account key", drain(c))
	}
	drain(c)
	candidate := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(local, candidate); err != nil {
		t.Fatal(err)
	}
	if info, err := a.infinite.accountInfo(primary); err != nil || info.PublicProfile.Score != 8 || info.TotalNames != 1 {
		t.Fatal("resetting P2 changed P1 account")
	}
	if info, err := a.infinite.accountInfo(candidate); err != nil || info.PublicProfile.Score != 13 || info.PublicProfile.Name != "Wing" {
		t.Fatal("P2 reset lost its score")
	}
	if _, err := a.infinite.accountInfo(local); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("old P2 key remained usable")
	}
	for _, controller := range []*Client{active, c} {
		packets := drain(controller)
		found := false
		for _, packet := range packets {
			if packet["code"] == "account_key_revoked" && packet["seat"] == float64(1) {
				found = true
			}
			if strings.Contains(fmt.Sprint(packet), candidate) {
				t.Fatal("new P2 key leaked to old controller")
			}
		}
		if !found {
			t.Fatal("old pair lacked P2 revocation notice", packets)
		}
	}
	if !r.contains(p) || r.contains(child) || p.PublicToken != primary || p.Client != nil {
		t.Fatal("P2 reset removed P1 proof or retained delegated P2 authority")
	}
	resumer := fakeClient()
	action(t, a.hub, resumer, map[string]any{"type": "join", "code": r.Code, "token": roomToken, "name": "Primary", "publicToken": primary, "independentAccounts": true})
	if resumer.player != p || roomLocalController(r, p) != nil {
		t.Fatal("unaffected room token could not resume P1 alone", drain(resumer))
	}
	for _, packet := range drain(resumer) {
		if strings.Contains(fmt.Sprint(packet), candidate) || packet["localPublicToken"] == local {
			t.Fatal("old P1 room token recovered revoked or replacement P2 key")
		}
	}
}

func TestIndependentLegacyP2MigrationPreservesScoreAfterOfflineRename(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	legacy, old, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Old Wing"})
	legacy.pilot.Score, legacy.local.Score = 3, 42
	commitPublicFixture(t, a.infinite)
	id := legacy.local.ID
	upgraded, _, _, local := independentPair(t, a.infinite, "Primary", "Renamed Wing", primary)
	if upgraded.local.ID != id || upgraded.local.Score != 42 || upgraded.pilot.Score != 3 {
		t.Fatal("offline P2 rename discarded meaningful legacy score")
	}
	if a.infinite.publicProfiles[upgraded.pilot.publicKey].local != 0 || a.infinite.publicProfiles[upgraded.local.publicKey].primary != id {
		t.Fatal("legacy P2 was not split into its own primary profile")
	}
	info, _ := a.infinite.accountInfo(local)
	if strings.Join(info.Names, ",") != "Old Wing,Renamed Wing" || info.PublicProfile.Score != 42 {
		t.Fatal("legacy proven alias and score were not moved together", info)
	}
	if notices := drain(old); len(notices) != 1 || notices[0]["seat"] != float64(1) {
		t.Fatal("legacy paired transport was not signed out for P2 migration", notices)
	}
}

func TestIndependentPrivateFirstMigrationSurvivesRestartBeforeTick(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	legacy, _, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Old Wing"})
	legacy.local.Score = 38
	id := legacy.local.ID
	commitPublicFixture(t, a.infinite)
	c := fakeClient()
	action(t, a.hub, c, map[string]any{"type": "create", "name": "Primary", "publicToken": primary})
	local := freshAccountKey(t)
	action(t, a.hub, c, map[string]any{"type": "add", "kind": "local", "name": "Renamed Wing", "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	if roomLocalController(c.room, c.player) == nil || len(a.hub.callsigns.seatMigrations) != 1 {
		t.Fatal("private split did not save a migration marker", drain(c))
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	info, err := a.infinite.accountInfo(local)
	if err != nil || info.PublicProfile == nil || info.PublicProfile.Score != 38 || info.PublicProfile.Name != "Renamed Wing" || len(a.hub.callsigns.seatMigrations) != 0 {
		t.Fatalf("restart lost private-first migration: %+v %v", info, err)
	}
	restored, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: local, IndependentAccounts: true})
	if restored.pilot.ID != id || restored.pilot.Score != 38 {
		t.Fatal("private-first migrated P2 did not resume as P1")
	}
}

func TestIndependentPrivateMigrationRevokesLegacyInputBeforeNextTick(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	legacy, old, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Old Wing"})
	legacy.local.Score = 22
	commitPublicFixture(t, a.infinite)
	legacyRoom := fakeClient()
	action(t, a.hub, legacyRoom, map[string]any{"type": "create", "name": "Primary", "publicToken": primary})
	action(t, a.hub, legacyRoom, map[string]any{"type": "add", "kind": "local", "name": "Old Wing"})
	legacySeat := roomLocalController(legacyRoom.room, legacyRoom.player)
	legacySeat.Input.Fire, legacySeat.FirePending = true, true
	c := fakeClient()
	action(t, a.hub, c, map[string]any{"type": "create", "name": "Primary", "publicToken": primary})
	local := freshAccountKey(t)
	action(t, a.hub, c, map[string]any{"type": "add", "kind": "local", "name": "Renamed Wing", "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	if legacyRoom.room.contains(legacySeat) || legacySeat.Input.Fire || legacySeat.FirePending {
		t.Fatal("old legacy private P2 retained delegated authority after split")
	}
	a.infinite.step(time.Now())
	legacy.arena.setConnectionInput(old, legacy.pilot, legacy.local, Input{Seq: 99, Fire: true, Forward: true}, false, time.Now())
	if legacy.pilot.client != nil || legacy.local.input.Fire || legacy.local.input.Forward || a.infinite.public.players != 0 {
		t.Fatal("legacy shared public pair retained control after private-first split")
	}
	info, err := a.infinite.accountInfo(local)
	if err != nil || info.PublicProfile.Score != 22 || info.PublicProfile.Name != "Renamed Wing" {
		t.Fatal("retiring old shared transport overwrote migrated name or score", info, err)
	}
}

func TestIndependentPrivateResumeOnlyReplacesActuallyUnusedCandidate(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	c := fakeClient()
	a.hub.addClient(c)
	action(t, a.hub, c, map[string]any{"type": "create", "name": "Primary", "independentAccounts": true})
	local := freshAccountKey(t)
	action(t, a.hub, c, map[string]any{"type": "add", "kind": "local", "name": "Wing", "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	r, p := c.room, c.player
	a.hub.removeClient(c)
	other, _ := a.hub.callsigns.claim("", []string{"Imported"})
	for _, attempt := range []struct {
		key   string
		fresh bool
	}{{other, false}, {other, true}, {"p_bad", true}} {
		rejected := fakeClient()
		action(t, a.hub, rejected, map[string]any{"type": "join", "code": r.Code, "token": p.Token, "name": p.Name, "publicToken": p.PublicToken, "localPublicToken": attempt.key, "localNewAccount": attempt.fresh, "independentAccounts": true})
		if rejected.player != nil || !hasError(rejected, "account_seat_conflict") {
			t.Fatal("private room resume overwrote an imported or already registered P2 key")
		}
	}
	unused := freshAccountKey(t)
	resumed := fakeClient()
	action(t, a.hub, resumed, map[string]any{"type": "join", "code": r.Code, "token": p.Token, "name": p.Name, "publicToken": p.PublicToken, "localPublicToken": unused, "localNewAccount": true, "independentAccounts": true})
	if resumed.player != p || resumed.localOwnerToken != local {
		t.Fatal("authenticated private resume did not recover existing P2", drain(resumed))
	}
	if _, known := a.hub.callsigns.owner(unused); known {
		t.Fatal("unused recovery candidate allocated an account")
	}
	for _, packet := range drain(resumed) {
		if packet["type"] == "welcome" && packet["localPublicToken"] != local {
			t.Fatal("welcome omitted existing P2 key")
		}
		if packet["type"] != "welcome" && packet["type"] != "identity" {
			data, _ := json.Marshal(packet)
			if strings.Contains(string(data), local) {
				t.Fatal("P2 key leaked in a broadcast packet")
			}
		}
	}
}

func TestIndependentImportedP2DoesNotMergeLegacyScores(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	legacy, _, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Legacy Wing"})
	legacyID := legacy.local.ID
	legacy.local.Score = 37
	imported, _, importedKey := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Imported"})
	imported.pilot.Score = -6
	commitPublicFixture(t, a.infinite)
	paired, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: primary, LocalPublicToken: importedKey, Name: "Primary", LocalName: "Imported", IndependentAccounts: true, UpdateNames: true})
	if paired.local.ID != imported.pilot.ID || paired.local.Score != -6 || a.infinite.public.publicEntries[legacyID].Score != 37 {
		t.Fatal("importing an existing P2 merged or discarded another account's legacy score")
	}
	fresh, _, _, key := independentPair(t, a.infinite, "Primary", "Fresh Wing", primary)
	info, err := a.infinite.accountInfo(key)
	if err != nil || fresh.local.ID != legacyID || fresh.local.Score != 37 || info.PublicProfile.Score != 37 {
		t.Fatal("archived legacy score was not retained for a later authorized split")
	}
	info, err = a.infinite.accountInfo(importedKey)
	if err != nil || info.PublicProfile.Score != -6 {
		t.Fatal("replacing local account changed imported P2 score")
	}
}

func TestIndependentZeroScoreP2CannotBePrunedWhileActiveOrReserved(t *testing.T) {
	a := accountAppFixture(t, "")
	pair, active, _, key := independentPair(t, a.infinite, "Primary", "Wing", "")
	hash, _ := publicTokenHash(key)
	profile := a.infinite.publicProfiles[hash]
	profile.used = time.Now().Add(-40 * 24 * time.Hour).Unix()
	a.infinite.publicProfiles[hash] = profile
	for i := 0; i < infiniteZeroProfiles; i++ {
		id := 100000 + i
		owner := fmt.Sprintf("%064x", i)
		a.infinite.publicProfiles[owner] = infinitePublicProfile{hash: owner, primary: id, used: time.Now().Unix()}
		a.infinite.publicZeroProfiles[owner] = true
		a.infinite.public.publicEntries[id] = infinitePublicEntry{infiniteLeader: infiniteLeader{ID: id, Name: "CHURN"}}
	}
	for _, reserved := range []bool{false, true} {
		if reserved {
			delete(a.infinite.connections, active)
			reservation := infiniteRoomPilot{room: infiniteRoom{room: &Room{}, generation: 1}, seat: &Player{}}
			a.infinite.reservations[reservation] = infiniteReservation{connection: pair, until: time.Now().Add(time.Second)}
		}
		a.infinite.mu.Lock()
		err := a.infinite.prunePublicProfiles(time.Now())
		a.infinite.mu.Unlock()
		if err != nil {
			t.Fatal(err)
		}
		if _, exists := a.infinite.publicProfiles[hash]; !exists {
			t.Fatal("active or reserved P2 account was pruned")
		}
	}
}

func TestIndependentLegacySocketCannotAcquireTheOtherSeat(t *testing.T) {
	for _, seat := range []int{0, 1} {
		t.Run(fmt.Sprint(seat), func(t *testing.T) {
			a := accountAppFixture(t, "")
			pair, old, primary, local := independentPair(t, a.infinite, "Primary", "Wing", "")
			server := httptest.NewServer(a.handler())
			t.Cleanup(server.Close)
			key, other, id := primary, local, pair.pilot.ID
			if seat == 1 {
				key, other, id = local, primary, pair.local.ID
			}
			socket, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "publicToken": key}, false)
			var welcome map[string]any
			readInfinitePacket(t, reader, &welcome)
			if welcome["type"] != "welcome" || welcome["id"] != float64(id) || welcome["publicToken"] != key || welcome["localId"] != nil || welcome["localPublicToken"] != nil || strings.Contains(fmt.Sprint(welcome), other) {
				t.Fatal("omitting independent flag acquired another seat or its key", welcome)
			}
			notices := drain(old)
			if len(notices) != 1 || notices[0]["code"] != "session_replaced" || notices[0]["seat"] != float64(seat) {
				t.Fatal("wrong affected takeover seat", notices)
			}
			pair.arena.setConnectionInput(old, pair.pilot, pair.local, Input{Seq: 99, Fire: true}, false, time.Now())
			if _, err := socket.Write(maskedFrame(1, true, []byte(`{"type":"rename","seat":1,"requestId":1,"name":"Stolen"}`))); err != nil {
				t.Fatal(err)
			}
			var denial map[string]any
			readInfinitePacket(t, reader, &denial)
			if denial["type"] != "rename_error" {
				t.Fatal("single proof renamed absent P2", denial)
			}
			a.infinite.mu.Lock()
			a.infinite.public.mu.Lock()
			counts := make(map[int]int)
			for _, pilot := range a.infinite.public.pilots {
				if !pilot.Bot {
					counts[pilot.ID]++
				}
			}
			if len(counts) != 1 || counts[id] != 1 || pair.local.input.Fire || pair.pilot.input.Fire {
				t.Error("legacy handover duplicated a body or retained old paired authority", counts)
			}
			a.infinite.public.mu.Unlock()
			a.infinite.mu.Unlock()
			if _, err := socket.Write(maskedFrame(1, true, []byte(`{"type":"input","local":true,"seq":1,"fire":true}`))); err != nil {
				t.Fatal(err)
			}
			// A controller with only one proof has no P2 input route. The server
			// closes it rather than guessing an existing paired body from its ID.
			var header [2]byte
			if _, err := reader.Read(header[:]); err != nil || header[0]&15 != 8 {
				t.Fatal("absent P2 input did not close the unauthorized route", header, err)
			}
		})
	}
}
