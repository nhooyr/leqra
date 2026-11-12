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

func TestOnlineCallsignClaimsAreAtomicDurableAndOwnerBound(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	registry := s.hub.callsigns
	owner, err := registry.claim("", []string{"Snow", "Wing"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = registry.claim("", []string{"snow"}); err == nil {
		t.Fatal("callsign was claimed by case variant")
	}
	if _, err = registry.claim("", []string{"New", "WING"}); err == nil {
		t.Fatal("conflicting local seat was accepted")
	}
	if got := registry.availability("", []string{"New"}); !got[0].Available {
		t.Fatal("failed pair consumed nonconflicting name")
	}
	if _, err = registry.claim(owner, []string{"SNOW", "Wing"}); err != nil {
		t.Fatal("owner could not reuse names")
	}
	if _, err = registry.claim(owner, []string{"Snow", "snow"}); err == nil {
		t.Fatal("same owner duplicated local names")
	}
	if _, err = registry.claim("p_forged", []string{"New"}); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("forged owner was accepted")
	}
	if _, err = s.ResetPublicLeaderboard(); err != nil {
		t.Fatal(err)
	}
	s.close()
	s = publicStoreFixture(t, path)
	registry = s.hub.callsigns
	if _, err = registry.claim("", []string{"snow"}); err == nil {
		t.Fatal("reset/restart released permanent callsign claim")
	}
	if _, err = registry.claim(owner, []string{"Snow", "Wing"}); err != nil {
		t.Fatal("restart lost owner proof")
	}
	if got := registry.availability(owner, []string{"sNoW", "Other"}); !got[0].Available || !got[1].Available {
		t.Fatal("read-only availability did not recognize owner")
	}
	p, _, same := savedPublicJoin(t, s, infiniteMessage{PublicToken: owner, Name: "Snow", LocalName: "Wing", Resume: true})
	if same != owner || p.pilot.Score != 0 || p.local == nil {
		t.Fatal("private owner without score profile could not enter public arena")
	}
}

func TestOnlineCallsignClaimRaceHasSingleWinner(t *testing.T) {
	registry := newOnlineCallsignRegistry()
	start := make(chan struct{})
	var wg sync.WaitGroup
	results := make(chan error, 32)
	for range 32 {
		wg.Add(1)
		go func() { defer wg.Done(); <-start; _, err := registry.claim("", []string{"Racer"}); results <- err }()
	}
	close(start)
	wg.Wait()
	close(results)
	wins := 0
	for err := range results {
		if err == nil {
			wins++
		}
	}
	if wins != 1 || len(registry.owners) != 1 {
		t.Fatalf("claim race allocated %d winners/%d owners", wins, len(registry.owners))
	}
}

func TestOnlineCallsignUnicodeCaseFolding(t *testing.T) {
	registry := newOnlineCallsignRegistry()
	if _, err := registry.claim("", []string{"Σnow"}); err != nil {
		t.Fatal(err)
	}
	if _, err := registry.claim("", []string{"ςNOW"}); err == nil {
		t.Fatal("Unicode case variant escaped name ownership")
	}
}

func TestCallsignAvailabilityIsReadOnlyAndNeverLeaksOwner(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	token, err := app.hub.callsigns.claim("", []string{"Claimed"})
	if err != nil {
		t.Fatal(err)
	}
	for _, owned := range []bool{false, true} {
		proof := ""
		if owned {
			proof = token
		}
		body, _ := json.Marshal(map[string]any{"publicToken": proof, "names": []string{"claimed", "Unused"}})
		request := httptest.NewRequest("POST", "http://leqra.test/api/callsigns", strings.NewReader(string(body)))
		request.Header.Set("Origin", "http://leqra.test")
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		app.handler().ServeHTTP(response, request)
		var result struct{ Names []callsignAvailability }
		if err = json.Unmarshal(response.Body.Bytes(), &result); err != nil || response.Code != 200 {
			t.Fatalf("availability %d %s", response.Code, response.Body.String())
		}
		if len(result.Names) != 2 || result.Names[0].Available != owned || !result.Names[1].Available {
			t.Fatal("incorrect owner availability")
		}
		hash, _ := publicTokenHash(token)
		if strings.Contains(response.Body.String(), token) || strings.Contains(response.Body.String(), hash) {
			t.Fatal("availability exposed private credential")
		}
	}
	if len(app.hub.callsigns.claims) != 1 || len(app.hub.callsigns.owners) != 1 || len(app.infinite.publicProfiles) != 0 {
		t.Fatal("availability allocated identity or claimed name")
	}
}

func TestPublicCallsignRenameClaimsBeforeMutatingScoreIdentity(t *testing.T) {
	s := publicStoreFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	first, c, token := savedPublicJoin(t, s, infiniteMessage{Name: "First", LocalName: "Wing"})
	savedPublicJoin(t, s, infiniteMessage{Name: "Taken"})
	s.renamePilot(c, infiniteMessage{RequestID: 1, Name: "taken"}, time.Now())
	messages := drain(c)
	if len(messages) != 1 || messages[0]["code"] != "callsign_taken" || first.pilot.Name != "First" {
		t.Fatal("conflicting rename mutated name or omitted seat conflict")
	}
	s.renamePilot(c, infiniteMessage{RequestID: 2, Name: "New"}, time.Now())
	drain(c)
	if first.pilot.Name != "New" {
		t.Fatal("available rename failed")
	}
	if got := s.hub.callsigns.availability("", []string{"First", "new", "Wing"}); got[0].Available || got[1].Available || got[2].Available {
		t.Fatal("rename released historical aliases")
	}
	if got := s.hub.callsigns.availability(token, []string{"First", "New"}); !got[0].Available || !got[1].Available {
		t.Fatal("owner lost renamed alias")
	}
}

func TestCallsignAvailabilityRejectsSpoofingAndMalformedBodies(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	for _, tc := range []struct {
		origin, content, body string
		status                int
	}{
		{"https://evil.test", "application/json", `{"names":["Name"]}`, 403},
		{"", "application/json", `{"names":["Name"]}`, 403},
		{"http://leqra.test", "text/plain", `{"names":["Name"]}`, 415},
		{"http://leqra.test", "application/json", `{"names":["Name"],"score":99}`, 400},
		{"http://leqra.test", "application/json", `{"names":["Name"]}{"score":99}`, 400},
		{"http://leqra.test", "application/json", `{"names":["Name"],"publicToken":"p_forged"}`, 200},
	} {
		request := httptest.NewRequest("POST", "http://leqra.test/api/callsigns", strings.NewReader(tc.body))
		request.Header.Set("Origin", tc.origin)
		request.Header.Set("Content-Type", tc.content)
		response := httptest.NewRecorder()
		app.handler().ServeHTTP(response, request)
		if response.Code != tc.status {
			t.Fatalf("%q %q =>%d want%d", tc.origin, tc.body, response.Code, tc.status)
		}
	}
	if len(app.hub.callsigns.owners) != 0 || len(app.hub.callsigns.claims) != 0 {
		t.Fatal("availability allocated an unauthenticated identity")
	}
}

func TestOnlineCallsignShutdownWithConcurrentAvailability(t *testing.T) {
	s := publicStoreFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	registry := s.hub.callsigns
	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			_, _ = registry.claim("", []string{fmt.Sprintf("Closing %d", i)})
			registry.availability("", []string{"Closing"})
		}(i)
	}
	done := make(chan struct{})
	go func() { <-start; s.close(); wg.Wait(); close(done) }()
	close(start)
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("database close deadlocked name claim/availability")
	}
}

func TestOnlineCallsignRejectsMalformedPersistedOwnerHash(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	if _, err := s.publicDB.Exec("INSERT INTO online_owners(token_hash) VALUES(?)", strings.Repeat("z", 64)); err != nil {
		t.Fatal(err)
	}
	s.close()
	restored := newInfiniteServer(newHub(4))
	if err := restored.openPublicStore(path); err == nil {
		restored.close()
		t.Fatal("malformed persisted owner hash did not fail startup")
	}
}
