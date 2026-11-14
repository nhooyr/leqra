package main

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"sync"
	"testing"
)

func generationID(n int) string { return fmt.Sprintf("01234567-89ab-4cde-8012-%012x", n) }

func generateNames(t *testing.T, a *App, id string, accounts []callsignGenerationAccount) []generatedCallsign {
	t.Helper()
	rows := make([]map[string]any, len(accounts))
	for i, account := range accounts {
		rows[i] = map[string]any{"seat": account.Seat, "publicToken": account.PublicToken}
	}
	body, _ := json.Marshal(map[string]any{"requestId": id, "accounts": rows})
	w := accountRequest(a, "/api/callsigns/generate", string(body))
	var response struct {
		Names []generatedCallsign `json:"names"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &response) != nil {
		t.Fatalf("generate: %d %s", w.Code, w.Body.String())
	}
	return response.Names
}

func TestCallsignGenerationAtomicallyClaimsIndependentSeatsAndRetriesAcrossRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	accounts := []callsignGenerationAccount{{Seat: 1, PublicToken: freshAccountKey(t)}, {Seat: 0, PublicToken: freshAccountKey(t)}}
	names := generateNames(t, a, generationID(1), accounts)
	pattern := regexp.MustCompile(`^pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$`)
	if len(names) != 2 || names[0].Seat != 0 || names[1].Seat != 1 || names[0].Name == names[1].Name {
		t.Fatal("generation did not preserve independent slot ownership", names)
	}
	for _, row := range names {
		if !pattern.MatchString(row.Name) || len(row.Name) != 12 || cleanCallsign(row.Name) != row.Name {
			t.Fatal("invalid random default", row)
		}
	}
	if retry := generateNames(t, a, strings.ToUpper(generationID(1)), accounts); !reflect.DeepEqual(retry, names) || len(a.hub.callsigns.claims) != 2 {
		t.Fatal("same request allocated more aliases", retry)
	}
	for _, account := range accounts {
		info, err := a.infinite.accountInfo(account.PublicToken)
		if err != nil || info.TotalNames != 1 || info.PublicProfile != nil {
			t.Fatal("generation changed a score profile or lost ownership", info, err)
		}
	}
	if a.infinite.public.players != 0 || len(a.infinite.connections) != 0 || len(a.hub.rooms) != 0 {
		t.Fatal("generation joined or replaced a transport")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if retry := generateNames(t, a, generationID(1), accounts); !reflect.DeepEqual(retry, names) || len(a.hub.callsigns.claims) != 2 {
		t.Fatal("restart broke retry idempotency", retry)
	}
	localOnly := generateNames(t, a, generationID(1), accounts[:1])
	if len(localOnly) != 1 || localOnly[0] != names[1] {
		t.Fatal("P2-only retry changed its batch-generated name")
	}
	fresh := generateNames(t, a, generationID(2), accounts)
	if fresh[0].Name == names[0].Name || fresh[1].Name == names[1].Name || len(a.hub.callsigns.claims) != 4 {
		t.Fatal("manual new request did not generate new aliases")
	}
}

func TestCallsignGenerationRetainsLegacyOwnedCollisionRetryAcrossRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	key, err := a.hub.callsigns.claim("", nil)
	if err != nil {
		t.Fatal(err)
	}
	id := generationID(20)
	blocked := legacyGeneratedCallsignCandidate(key, id, 0)
	legacy := legacyGeneratedCallsignCandidate(key, id, 1)
	if _, err := a.hub.callsigns.claim("", []string{blocked}); err != nil {
		t.Fatal(err)
	}
	if _, err := a.hub.callsigns.claim(key, []string{legacy}); err != nil {
		t.Fatal(err)
	}
	for restart := 0; restart < 2; restart++ {
		names := generateNames(t, a, id, []callsignGenerationAccount{{Seat: 0, PublicToken: key}})
		if len(names) != 1 || names[0].Name != legacy || len(a.hub.callsigns.claims) != 2 {
			t.Fatal("legacy retry allocated or changed its owned alias", names)
		}
		if restart == 0 {
			a.infinite.close()
			a = accountAppFixture(t, path)
		}
	}
	fresh := generateNames(t, a, generationID(21), []callsignGenerationAccount{{Seat: 0, PublicToken: key}})
	if len(fresh) != 1 || !strings.HasPrefix(fresh[0].Name, "pilot#") || len(a.hub.callsigns.claims) != 3 {
		t.Fatal("fresh UUID did not use the new generated format", fresh)
	}
	if !a.hub.callsigns.availability(key, []string{legacy, fresh[0].Name})[0].Available {
		t.Fatal("new generation lost the legacy alias")
	}
}

func TestCleanCallsignPreservesHashWithoutChangingCanonicalOwnership(t *testing.T) {
	r := newOnlineCallsignRegistry()
	key, err := r.claim("", []string{"pilot#ABC234"})
	if err != nil || cleanCallsign(" pilot#ABC234 ") != "pilot#ABC234" {
		t.Fatal("hash callsign was modified", err)
	}
	if !r.availability(key, []string{"PILOT#abc234"})[0].Available || r.availability("", []string{"PILOT#abc234"})[0].Available {
		t.Fatal("hash alias lost case-insensitive owner protection")
	}
	if !r.availability("", []string{"pilotABC234"})[0].Available {
		t.Fatal("hash alias collided with a distinct non-hash name")
	}
}

func TestCallsignGenerationRetriesOtherOwnerCollisionsAndRollsBackBatchFailure(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	first, second := freshAccountKey(t), freshAccountKey(t)
	blocked := generatedCallsignCandidate(first, generationID(3), 0)
	other, err := a.hub.callsigns.claim("", []string{blocked})
	if err != nil {
		t.Fatal(err)
	}
	names := generateNames(t, a, generationID(3), []callsignGenerationAccount{{Seat: 0, PublicToken: first}})
	if names[0].Name == blocked || names[0].Name != generatedCallsignCandidate(first, generationID(3), 1) {
		t.Fatal("generator took another owner's callsign")
	}
	if !a.hub.callsigns.availability(other, []string{blocked})[0].Available {
		t.Fatal("collision changed existing ownership")
	}
	third := freshAccountKey(t)
	if _, err := a.infinite.publicDB.Exec(`CREATE TRIGGER generation_fail BEFORE INSERT ON online_callsigns WHEN NEW.display_name='` + generatedCallsignCandidate(second, generationID(4), 0) + `' BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	request := fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":0,"publicToken":%q},{"seat":1,"publicToken":%q}]}`, generationID(4), third, second)
	w := accountRequest(a, "/api/callsigns/generate", request)
	if w.Code != 503 || len(a.hub.callsigns.owners) != 2 || len(a.hub.callsigns.claims) != 2 {
		t.Fatal("database failure partially claimed accounts", w.Code, w.Body.String())
	}
	for _, key := range []string{second, third} {
		if _, known := a.hub.callsigns.owner(key); known {
			t.Fatal("rolled-back account became valid")
		}
	}
	var count int
	if err := a.infinite.publicDB.QueryRow("SELECT COUNT(*) FROM online_owners").Scan(&count); err != nil || count != 2 {
		t.Fatal("database retained a partial owner", count, err)
	}
}

func TestCallsignGenerationConcurrentRetriesMintOneAliasPerSeat(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	keys := []string{freshAccountKey(t), freshAccountKey(t)}
	body := fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":0,"publicToken":%q},{"seat":1,"publicToken":%q}]}`, generationID(5), keys[0], keys[1])
	var wg sync.WaitGroup
	results := make(chan string, 10)
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			w := accountRequest(a, "/api/callsigns/generate", body)
			if w.Code != 200 {
				results <- fmt.Sprint(w.Code)
			} else {
				results <- w.Body.String()
			}
		}()
	}
	wg.Wait()
	close(results)
	first := ""
	for result := range results {
		if first == "" {
			first = result
		}
		if result != first || !strings.Contains(result, `"names"`) {
			t.Fatal("concurrent retries diverged", first, result)
		}
	}
	if len(a.hub.callsigns.claims) != 2 || len(a.hub.callsigns.owners) != 2 {
		t.Fatal("concurrent retries created extra aliases")
	}
}

func TestCallsignGenerationRejectsMalformedForgedAndRevokedBatches(t *testing.T) {
	a := accountAppFixture(t, "")
	key := freshAccountKey(t)
	validAccount := fmt.Sprintf(`{"seat":0,"publicToken":%q}`, key)
	for _, body := range []string{
		`{}`, `{"requestId":"bad","accounts":[` + validAccount + `]}`,
		fmt.Sprintf(`{"requestId":%q,"accounts":[]}`, generationID(6)),
		fmt.Sprintf(`{"requestId":%q,"accounts":[%s,%s]}`, generationID(6), validAccount, validAccount),
		fmt.Sprintf(`{"requestId":%q,"accounts":[%s,{"seat":1,"publicToken":%q}]}`, generationID(6), validAccount, key),
		fmt.Sprintf(`{"requestId":%q,"accounts":[{"publicToken":%q}]}`, generationID(6), key),
		fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":0}]}`, generationID(6)),
		fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":2,"publicToken":%q}]}`, generationID(6), key),
		fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":0,"publicToken":"p_bad"}]}`, generationID(6)),
		fmt.Sprintf(`{"requestId":%q,"accounts":[%s],"score":100}`, generationID(6), validAccount),
		fmt.Sprintf(`{"requestId":%q,"accounts":[%s]} {}`, generationID(6), validAccount), strings.Repeat("x", 2048),
	} {
		w := accountRequest(a, "/api/callsigns/generate", body)
		if w.Code != 400 || len(a.hub.callsigns.owners) != 0 {
			t.Fatalf("invalid generation accepted: %d %s", w.Code, w.Body.String())
		}
	}
	old, _ := a.hub.callsigns.claim("", []string{"Owner"})
	if _, err := a.infinite.rotateAccount(old, freshAccountKey(t)); err != nil {
		t.Fatal(err)
	}
	body := fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":0,"publicToken":%q},{"seat":1,"publicToken":%q}]}`, generationID(7), key, old)
	w := accountRequest(a, "/api/callsigns/generate", body)
	if w.Code != 401 || !strings.Contains(w.Body.String(), `"seat":1`) || !strings.Contains(w.Body.String(), "account_key_revoked") {
		t.Fatal("revoked batch lacked affected-seat rejection", w.Code, w.Body.String())
	}
	if _, known := a.hub.callsigns.owner(key); known {
		t.Fatal("revoked paired request allocated its other seat")
	}
}

func TestCallsignGenerationHonorsOriginLimitsAndDoesNotTakeOverScores(t *testing.T) {
	a := accountAppFixture(t, "")
	pair, active, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Active"})
	pair.pilot.Score = 19
	commitPublicFixture(t, a.infinite)
	body := fmt.Sprintf(`{"requestId":%q,"accounts":[{"seat":0,"publicToken":%q}]}`, generationID(8), key)
	for _, test := range []struct {
		method, origin, content string
		code                    int
	}{{"GET", "http://leqra.test", "application/json", 405}, {"POST", "https://evil.test", "application/json", 403}, {"POST", "http://leqra.test", "text/plain", 415}} {
		r := httptest.NewRequest(test.method, "http://leqra.test/api/callsigns/generate", strings.NewReader(body))
		r.Header.Set("Origin", test.origin)
		r.Header.Set("Content-Type", test.content)
		w := httptest.NewRecorder()
		a.handler().ServeHTTP(w, r)
		if w.Code != test.code {
			t.Fatal("generation weakened HTTP/origin restrictions", w.Code)
		}
	}
	generateNames(t, a, generationID(8), []callsignGenerationAccount{{Seat: 0, PublicToken: key}})
	if pair.pilot.client != active || pair.pilot.Score != 19 || len(drain(active)) != 0 || len(a.infinite.publicProfiles) != 1 {
		t.Fatal("alias generation mutated a live account")
	}
	b := accountAppFixture(t, "")
	for i := 0; i < 120; i++ {
		w := accountRequest(b, "/api/callsigns/generate", body)
		if w.Code != 200 {
			t.Fatal("budget rejected valid retry", i, w.Code)
		}
	}
	w := accountRequest(b, "/api/callsigns/generate", body)
	if w.Code != 429 || w.Header().Get("Retry-After") == "" {
		t.Fatal("generation omitted source budget")
	}
	if len(b.hub.callsigns.claims) != 1 {
		t.Fatal("rate-limited retries multiplied aliases")
	}
}
