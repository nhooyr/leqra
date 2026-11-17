package main

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestInfinityJoinUsesProtocolEpoch(t *testing.T) {
	for _, tt := range []struct {
		name        string
		fields      map[string]any
		wantSuccess bool
	}{
		{"different release with matching protocol", map[string]any{"version": "999.0.0", "protocol": protocolVersion}, true},
		{"matching release with incompatible protocol", map[string]any{"version": version, "protocol": protocolVersion + 1}, false},
		{"legacy join without protocol", map[string]any{"version": "999.0.0"}, protocolVersion == legacyInfinityProtocol},
		{"explicit zero protocol", map[string]any{"version": version, "protocol": 0}, false},
		{"explicit null protocol", map[string]any{"version": version, "protocol": nil}, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			tt.fields["type"] = "join"
			tt.fields["name"] = "Pilot"
			payload, err := json.Marshal(tt.fields)
			if err != nil {
				t.Fatal(err)
			}
			join, rejection := decodeInfiniteJoin(payload)
			if tt.wantSuccess {
				if rejection != nil || join.Name != "Pilot" {
					t.Fatalf("compatible join failed: %#v", rejection)
				}
			} else if rejection["code"] != "version_mismatch" || rejection["action"] != "version" || rejection["serverVersion"] != version || rejection["protocol"] != protocolVersion {
				t.Fatalf("expected protocol mismatch with server metadata, got %#v", rejection)
			}
		})
	}
}

func TestInfinityWelcomesAdvertiseProtocolEpoch(t *testing.T) {
	arena := newInfiniteArena()
	pilot, spectator := fakeClient(), fakeClient()
	if !arena.welcome(pilot, &infinitePilot{}, nil, 1, false) || !arena.addObserver(spectator, &infiniteObserver{}, 1, false, 0) {
		t.Fatal("failed to enqueue Infinity welcome")
	}
	for _, c := range []*Client{pilot, spectator} {
		packets := drain(c)
		if len(packets) == 0 || packets[0]["type"] != "welcome" || packets[0]["protocol"] != float64(protocolVersion) {
			t.Fatalf("welcome did not advertise the protocol epoch: %#v", packets)
		}
	}
}

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
