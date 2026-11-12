package main

import (
	"testing"
	"time"
)

func TestPrimaryCallsignDefaultsToPlayerOneWithoutRenamingChosenCallsigns(t *testing.T) {
	for _, name := range []string{"", " \t\n", "💥<>"} {
		if got := cleanName(name); got != "Player 1" {
			t.Fatalf("empty callsign %q became %q", name, got)
		}
	}
	for _, name := range []string{"PILOT", "Pilot", "YOU", "Player 1", "Snow Fox"} {
		if got := cleanName(name); got != name {
			t.Fatalf("chosen callsign %q became %q", name, got)
		}
	}
	for _, kind := range []string{"create", "join"} {
		h, c := newHub(4), fakeClient()
		action(t, h, c, map[string]any{"type": kind, "code": "FRESH"})
		if c.player == nil || c.player.Name != "Player 1" {
			t.Fatalf("%s did not assign the primary default", kind)
		}
	}
}

func TestPrimaryDefaultDoesNotReplaceBotOrCopilotDefaults(t *testing.T) {
	for kind, want := range map[string]string{"bot": "BOT", "local": "CO-PILOT"} {
		for _, name := range []string{"", "💥<>"} {
			h, c := newHub(4), fakeClient()
			action(t, h, c, map[string]any{"type": "create"})
			action(t, h, c, map[string]any{"type": "add", "kind": kind, "name": name})
			p := c.room.Players[1]
			if p == nil || p.Name != want {
				t.Fatalf("%s callsign %q did not retain %q: %+v", kind, name, want, p)
			}
		}
	}
}

func TestPublicInfinityUsesPlayerOneForAnUnnamedPrimary(t *testing.T) {
	for _, name := range []string{"", " \t", "PILOT"} {
		s := newInfiniteServer(newHub(2))
		pair, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Name: name, LocalName: "WING"}, time.Now())
		want := "Player 1"
		if name == "PILOT" {
			want = name
		}
		if rejection != "" || pair.pilot == nil || pair.pilot.Name != want || pair.local == nil || pair.local.Name != "WING" {
			t.Fatalf("public Infinity changed the defaults or chosen names: %+v, %q", pair, rejection)
		}
	}
	a := newSeededInfiniteArena(23)
	_, local := a.joinSeats(fakeClient(), infiniteSeat{}, &infiniteSeat{}, 0, time.Now())
	if local == nil || local.Name != "CO-PILOT" {
		t.Fatal("unnamed co-pilot inherited the primary callsign default")
	}
}
