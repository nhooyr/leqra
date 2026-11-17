package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

func releaseFixtureRequest(a *App, key string) (int, bool) {
	response := accountRequest(a, "/api/account/release", fmt.Sprintf(`{"publicToken":%q}`, key))
	var value struct {
		Released bool `json:"released"`
	}
	_ = json.Unmarshal(response.Body.Bytes(), &value)
	return response.Code, value.Released
}
func TestAccountReleaseDeletesOwnScoreAndNameAndCannotAffectReuser(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	pair, active, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	pair.pilot.Score = 31
	commitPublicFixture(t, a.infinite)
	unrelated, _, other := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Bravo", IndependentAccounts: true})
	unrelated.pilot.Score = 9
	commitPublicFixture(t, a.infinite)
	if status, released := releaseFixtureRequest(a, key); status != 200 || !released {
		t.Fatal(status, released)
	}
	if _, exists := a.infinite.connections[active]; exists {
		t.Fatal("released account retained live authority")
	}
	if _, err := a.infinite.accountInfo(key); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("released key still authenticates", err)
	}
	if info, err := a.infinite.accountInfo(other); err != nil || info.PublicProfile.Score != 9 {
		t.Fatal("release changed another account", info, err)
	}
	fresh := freshAccountKey(t)
	if _, err := a.infinite.createAccount(fresh, "Alpha"); err != nil {
		t.Fatal(err)
	}
	next, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", PublicToken: fresh, IndependentAccounts: true})
	if next.pilot.Score != 0 || next.pilot.ID == pair.pilot.ID {
		t.Fatal("new owner inherited released score")
	}
	if status, released := releaseFixtureRequest(a, key); status != 200 || !released {
		t.Fatal("retry not idempotent")
	}
	if _, err := a.infinite.accountInfo(fresh); err != nil {
		t.Fatal("old-key retry released new owner", err)
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if status, released := releaseFixtureRequest(a, key); status != 200 || !released {
		t.Fatal("restart lost release idempotence")
	}
	if _, err := a.infinite.createAccount(key, "Other"); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("released key recreated account", err)
	}
}
func TestAccountReleaseRollsBackWithForeignKeysAndRetries(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, _, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	pair.pilot.Score = 17
	commitPublicFixture(t, a.infinite)
	if _, err := a.infinite.publicDB.Exec(`PRAGMA foreign_keys=ON`); err != nil {
		t.Fatal(err)
	}
	if _, err := a.infinite.publicDB.Exec(`CREATE TRIGGER fail_release BEFORE DELETE ON online_callsigns BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	if status, _ := releaseFixtureRequest(a, key); status != 503 {
		t.Fatal("failed release reported success", status)
	}
	if info, err := a.infinite.accountInfo(key); err != nil || info.PublicProfile.Score != 17 {
		t.Fatal("failed release partially removed account", info, err)
	}
	if _, err := a.infinite.publicDB.Exec("DROP TRIGGER fail_release"); err != nil {
		t.Fatal(err)
	}
	if status, released := releaseFixtureRequest(a, key); status != 200 || !released {
		t.Fatal("foreign-key release failed", status, released)
	}
	if err := a.infinite.persistPublicLocked(nil, nil); err != nil {
		t.Fatal("post-release write failed", err)
	}
	var count int
	if err := a.infinite.publicDB.QueryRow("SELECT COUNT(*) FROM infinity_scores WHERE id=?", pair.pilot.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("released score resurrected", count, err)
	}
}
func TestAccountReleaseRevokesPrivateRoomAndLegacyPair(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	h := a.hub
	pair, _, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", LocalName: "Wing"})
	pair.pilot.Score = 5
	pair.local.Score = 7
	commitPublicFixture(t, a.infinite)
	client := fakeClient()
	action(t, h, client, map[string]any{"type": "create", "name": "Alpha", "publicToken": key})
	action(t, h, client, map[string]any{"type": "add", "kind": "local", "name": "Wing"})
	room, player, roomToken := client.room, client.player, client.player.Token
	if status, released := releaseFixtureRequest(a, key); status != 200 || !released {
		t.Fatal(status, released)
	}
	if room.contains(player) || roomLocalController(room, player) != nil {
		t.Fatal("private seats retained released account")
	}
	if !client.accountRevoked {
		t.Fatal("old private socket may still mutate")
	}
	retry := fakeClient()
	body, _ := json.Marshal(map[string]any{"type": "join", "code": room.Code, "token": roomToken, "publicToken": key, "name": "Alpha"})
	_ = h.handle(retry, body, time.Now())
	if retry.player != nil {
		t.Fatal("room credential resurrected released seat")
	}
	if !h.callsigns.availability("", []string{"Alpha", "Wing"})[0].Available || !h.callsigns.availability("", []string{"Alpha", "Wing"})[1].Available {
		t.Fatal("legacy names not freed")
	}
}
func TestAccountReleaseRejectsUnknownRevokedOrMalformedKeys(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	for _, key := range []string{"invalid", freshAccountKey(t)} {
		if status, _ := releaseFixtureRequest(a, key); status != 401 {
			t.Fatal("unknown key accepted", status)
		}
	}
	key := freshAccountKey(t)
	if _, err := a.infinite.createAccount(key, "Alpha"); err != nil {
		t.Fatal(err)
	}
	replacement := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(key, replacement); err != nil {
		t.Fatal(err)
	}
	if status, _ := releaseFixtureRequest(a, key); status != 401 {
		t.Fatal("rotated old key released account", status)
	}
	if _, err := a.infinite.accountInfo(replacement); err != nil {
		t.Fatal("revoked key affected replacement", err)
	}
}

func TestAccountReleaseP2LeavesIndependentP1AccountUsable(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, _, primary, local := independentPair(t, a.infinite, "Alpha", "Wing", "")
	pair.pilot.Score = 19
	pair.local.Score = 23
	commitPublicFixture(t, a.infinite)
	c := fakeClient()
	action(t, a.hub, c, map[string]any{"type": "create", "name": "Alpha", "publicToken": primary, "independentAccounts": true})
	action(t, a.hub, c, map[string]any{"type": "add", "kind": "local", "name": "Wing", "localPublicToken": local, "independentAccounts": true})
	room, player := c.room, c.player
	if status, released := releaseFixtureRequest(a, local); status != 200 || !released {
		t.Fatal(status, released)
	}
	if !room.contains(player) || roomLocalController(room, player) != nil {
		t.Fatal("P2 release deleted primary seat or retained secondary")
	}
	info, err := a.infinite.accountInfo(primary)
	if err != nil || info.PublicProfile.Score != 19 {
		t.Fatal("P2 release affected P1 score", info, err)
	}
	if _, err := a.infinite.accountInfo(local); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("P2 key remains valid", err)
	}
}

func TestAccountReleaseIdentifiesAffectedPublicSeat(t *testing.T) {
	for _, seat := range []int{0, 1} {
		t.Run(fmt.Sprint("seat", seat), func(t *testing.T) {
			a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
			_, active, primary, local := independentPair(t, a.infinite, "Primary", "Wing", "")
			drain(active)
			keys := []string{primary, local}
			if status, released := releaseFixtureRequest(a, keys[seat]); status != 200 || !released {
				t.Fatal(status, released)
			}
			found := false
			for _, packet := range drain(active) {
				if packet["type"] == "error" && packet["code"] == "account_key_invalid" {
					found = true
					if packet["seat"] != float64(seat) {
						t.Fatal("release notice identified the wrong account", packet["seat"])
					}
				}
			}
			if !found {
				t.Fatal("active pair did not receive its release notice")
			}
			if _, err := a.infinite.accountInfo(keys[1-seat]); err != nil {
				t.Fatal("release invalidated the other account", err)
			}
		})
	}
}
