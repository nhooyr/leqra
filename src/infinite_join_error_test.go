package main

import (
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestInfinityJoinReportsImmutableCallsignAndAffectedSeat(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "accounts.sqlite"))
	keys := []string{freshAccountKey(t), freshAccountKey(t)}
	for seat, key := range keys {
		if _, err := a.infinite.createAccount(key, fmt.Sprintf("Pilot%d", seat)); err != nil {
			t.Fatal(err)
		}
	}
	server := httptest.NewServer(a.handler())
	defer server.Close()
	for seat := range keys {
		t.Run(fmt.Sprint(seat), func(t *testing.T) {
			names := []string{"Pilot0", "Pilot1"}
			names[seat] = "Different"
			_, reader := dialInfinite(t, server.URL, infiniteMessage{Type: "join", Version: version,
				Name: names[0], LocalName: names[1], PublicToken: keys[0], LocalPublicToken: keys[1],
				IndependentAccounts: true, UpdateNames: true}, false)
			var packet map[string]any
			readInfinitePacket(t, reader, &packet)
			if packet["type"] != "error" || packet["code"] != "callsign_immutable" || packet["seat"] != float64(seat) {
				t.Fatal("join rejection omitted stable account code or affected seat", packet)
			}
		})
	}
}
