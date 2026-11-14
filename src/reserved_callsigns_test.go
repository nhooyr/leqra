package main

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestReservedBotSpacePrefixMatchesCleanedHumanNamesOnly(t *testing.T) {
	r := newOnlineCallsignRegistry()
	for _, name := range []string{"Bot", "BOT ", "Bot 1", "bOt RUST", "  BOT  0001  ", "bot π"} {
		if !reservedCallsign(name) {
			t.Fatal("reserved prefix escaped", name)
		}
		if _, err := r.claim("", []string{"Unused", name}); err == nil {
			t.Fatal("reserved human name claimed", name)
		} else {
			var reserved *callsignReservedError
			if !errors.As(err, &reserved) || reserved.Conflicts[0].Seat != 1 {
				t.Fatal("reserved error looked like someone else's account", err)
			}
		}
		if row := r.availability("", []string{name})[0]; row.Available || row.Reason != "reserved" {
			t.Fatal("reserved name did not explain availability", row)
		}
		if len(r.owners) != 0 || len(r.claims) != 0 {
			t.Fatal("reserved batch partially allocated ownership")
		}
	}
	for _, name := range []string{"RUST", "Botanist", "BotRUST", "Bot-RUST", "Bot_RUST", "GODLIKE 1", "godlike-1", "Godlike Bot 1"} {
		if reservedCallsign(name) {
			t.Fatal("ordinary allowed human name was over-reserved", name)
		}
		if _, err := r.claim("", []string{name}); err != nil {
			t.Fatal("ordinary human name rejected", name, err)
		}
	}
}

func TestReservedLegacyAliasStaysOwnedButCannotBypassReservation(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	r := a.hub.callsigns
	key, _ := r.claim("", []string{"Allowed"})
	hash, _ := publicTokenHash(key)
	// Existing ownership is retained during upgrade; it does not grant a right
	// to keep using a newly reserved display name for a human tank.
	if _, err := r.db.Exec("INSERT INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?)", "bot 9", "Bot 9", hash); err != nil {
		t.Fatal(err)
	}
	r.claims["bot 9"] = hash
	r.names[hash]["bot 9"] = "Bot 9"
	if _, err := r.claim(key, []string{"BOT 9"}); err == nil {
		t.Fatal("existing owner bypassed reservation")
	}
	if row := r.availability(key, []string{"bOt 9"})[0]; row.Available || row.Reason != "reserved" {
		t.Fatal("owned reserved alias appeared usable")
	}
	if info, err := a.infinite.accountInfo(key); err != nil || info.TotalNames != 2 {
		t.Fatal("reservation deleted historical ownership", info, err)
	}
	local := freshAccountKey(t)
	if _, err := r.claimSeatAccounts([]accountSeatClaim{{token: key, name: "New Alias"}, {token: local, name: "Bot 9", newAccount: true, transferFrom: key}}, nil); err == nil {
		t.Fatal("independent P2 migration bypassed reserved prefix")
	}
	if _, known := r.owner(local); known || !r.availability("", []string{"New Alias"})[0].Available {
		t.Fatal("rejected migration partially changed claims")
	}
	pair, active, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: key, Name: "Allowed"})
	id := pair.pilot.ID
	pair.pilot.Name, pair.pilot.Score = "Bot 9", 23
	commitPublicFixture(t, a.infinite)
	a.infinite.remove(active)
	if _, client, reject := tryInfinityReconnect(t, a.infinite, infiniteMessage{PublicToken: key, Resume: true}, time.Now()); reject == "" || !client.callsignReserved {
		t.Fatal("saved reserved name bypassed recovery admission", reject)
	}
	repaired, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: key, Name: "Allowed", UpdateNames: true})
	if repaired.pilot.ID != id || repaired.pilot.Score != 23 {
		t.Fatal("repairing a legacy reserved name lost its score identity")
	}
}

func TestReservedCallsignsRejectRoomAndPublicHumanEntryPaths(t *testing.T) {
	a := accountAppFixture(t, "")
	h := a.hub
	for _, kind := range []string{"create", "join", "publish"} {
		c := fakeClient()
		request := map[string]any{"type": kind, "name": "Bot RUST", "code": "fresh"}
		if kind == "publish" {
			request["roster"] = []SeatSpec{{Kind: "human", Name: "Bot RUST"}}
		}
		action(t, h, c, request)
		if c.player != nil || !hasError(c, "callsign_reserved") {
			t.Fatal("human room admission escaped reservation", kind, drain(c))
		}
	}
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "create", "name": "Pilot"})
	action(t, h, c, map[string]any{"type": "add", "kind": "local", "name": "Wing"})
	local := roomLocalController(c.room, c.player)
	for _, request := range []map[string]any{
		{"type": "rename", "name": "Bot RUST"},
		{"type": "rename_local", "target": local.ID, "member": local.Member, "name": "Bot RUST"},
		{"type": "configure", "target": local.ID, "member": local.Member, "name": "Bot RUST"},
		{"type": "preset", "rules": defaultRules(), "roster": []SeatSpec{{Kind: "human", Name: "Pilot"}, {Kind: "local", Name: "Bot RUST"}}},
	} {
		drain(c)
		action(t, h, c, request)
		if !hasError(c, "callsign_reserved") || c.player.Name != "Pilot" || local.Name != "Wing" {
			t.Fatal("room mutation bypassed reserved identity", request, drain(c))
		}
	}
	action(t, h, c, map[string]any{"type": "add", "kind": "bot", "name": "Bot RUST", "difficulty": "normal"})
	if c.room.Players[2] == nil || c.room.Players[2].Name != "Bot RUST" {
		t.Fatal("custom bot names were incorrectly restricted")
	}
	for _, msg := range []infiniteMessage{{Name: "Bot RUST"}, {Name: "Pilot 2", LocalName: "Bot RUST"}, {Name: "Pilot 3", LocalName: "Bot RUST", LocalPublicToken: freshAccountKey(t), LocalNewAccount: true, IndependentAccounts: true}} {
		_, client, reject := tryInfinityReconnect(t, a.infinite, msg, time.Now())
		if reject == "" || !client.callsignReserved || !strings.Contains(reject, "reserved") {
			t.Fatal("public human admission bypassed reservation", reject)
		}
	}
	pair, active, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Public", LocalName: "Public Wing"})
	for seat := 0; seat < 2; seat++ {
		a.infinite.renamePilot(active, infiniteMessage{Name: "Bot RUST", Seat: seat, RequestID: uint64(seat + 1)}, time.Now())
		packets := drain(active)
		if len(packets) != 1 || packets[0]["type"] != "rename_error" || packets[0]["code"] != "callsign_reserved" {
			t.Fatal("Infinity rename bypassed reservation", seat, packets)
		}
	}
	if pair.pilot.Name != "Public" || pair.local.Name != "Public Wing" {
		t.Fatal("failed rename changed authoritative identity")
	}
}

func TestReservedAvailabilityExplainsBothSeatsWithoutImportHint(t *testing.T) {
	a := accountAppFixture(t, "")
	w := accountRequest(a, "/api/callsigns", `{"names":["Bot RUST","BOT 1"],"independentAccounts":true}`)
	var response struct {
		Names []callsignAvailability `json:"names"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &response) != nil || len(response.Names) != 2 {
		t.Fatal("availability failed", w.Code, w.Body.String())
	}
	for _, row := range response.Names {
		if row.Available || row.Reason != "reserved" {
			t.Fatal("P2 reason was lost", row)
		}
	}
}
