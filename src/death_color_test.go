package main

import (
	"bytes"
	"encoding/json"
	"os"
	"testing"
	"time"
)

func TestKillerColorsMatchSharedBrowserPaletteFixtures(t *testing.T) {
	raw, err := os.ReadFile("tests/killer-color-fixtures.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Index              int
		Canonical, Painted string
	}
	if err = json.Unmarshal(raw, &fixtures); err != nil {
		t.Fatal(err)
	}
	for _, fixture := range fixtures {
		if tankColors[fixture.Index] != fixture.Canonical {
			t.Fatalf("palette index%d: %q != %q", fixture.Index, tankColors[fixture.Index], fixture.Canonical)
		}
		a := newSeededInfiniteArena(37)
		shooter := a.addPilot("RUST", true, 0, 0, 0, 0)
		target := a.join(fakeClient(), "Victim", time.Now())
		shooter.ColorIndex = fixture.Index
		a.eliminatePilot(target, shooter.ID, 0, shooter.Name)
		if target.KilledByColor != fixture.Canonical {
			t.Fatalf("color%d captured %q", fixture.Index, target.KilledByColor)
		}
		a.spawn(target, target.X, target.Y, 2, 5)
		if target.KilledBy != "" || target.KilledByColor != "" {
			t.Fatal("new life retained old killer metadata")
		}
	}
}

func TestInfinityDeathColorsArePersonalizedForBothLocalVictimsWithoutLeakingIntoSharedViews(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	firstClient, otherClient := fakeClient(), fakeClient()
	first, second := a.joinSeats(firstClient, infiniteSeat{name: "FIRST"}, &infiniteSeat{name: "SECOND"}, 1, now)
	other := a.join(otherClient, "OTHER", now)
	bot := a.addPilot("BOT", true, 0, 0, 0, 0)
	for i, p := range a.pilots {
		p.X, p.Y = float64(42+i*10), 42
	}
	bot.ColorIndex = 5
	drain(firstClient)
	drain(otherClient)
	a.eliminatePilot(first, bot.ID, 0, bot.Name)
	a.eliminatePilot(second, bot.ID, 0, bot.Name)
	a.eliminatePilot(bot, other.ID, 0, other.Name)
	a.broadcast()
	firstRaw, otherRaw := <-firstClient.send, <-otherClient.send
	if bytes.Equal(firstRaw, otherRaw) {
		t.Fatal("personalized death metadata reused another pilot's wire frame")
	}
	decode := func(raw []byte) []map[string]any {
		t.Helper()
		var packet struct{ Tanks []map[string]any }
		if err := json.Unmarshal(raw, &packet); err != nil {
			t.Fatal(err)
		}
		return packet.Tanks
	}
	ownColors := 0
	for _, tank := range decode(firstRaw) {
		color, present := tank["killedByColor"]
		id := int(tank["id"].(float64))
		if id == first.ID || id == second.ID {
			if color != tankColors[5] {
				t.Fatalf("local victim%d lost killer color: %+v", id, tank)
			}
			ownColors++
		} else if present {
			t.Fatalf("remote victim leaked color into local frame: %+v", tank)
		}
	}
	if ownColors != 2 {
		t.Fatalf("local death colors=%d, want2", ownColors)
	}
	for _, tank := range decode(otherRaw) {
		if _, present := tank["killedByColor"]; present {
			t.Fatalf("another connection received private victim color: %+v", tank)
		}
	}
	a.spawn(first, 42, 42, 0, 0)
	a.spawn(second, 42, 42, 0, 0)
	a.spawn(bot, 42, 42, 0, 0)
	other.X, other.Y = 42, 42
	a.broadcast()
	for _, raw := range [][]byte{<-firstClient.send, <-otherClient.send} {
		for _, tank := range decode(raw) {
			if _, present := tank["killedByColor"]; present {
				t.Fatalf("respawn retained a color: %+v", tank)
			}
		}
	}
}

func TestInfinityProjectileKeepsGoneOwnerColorAndCallsign(t *testing.T) {
	a := newSeededInfiniteArena(37)
	client := fakeClient()
	target := a.join(client, "VICTIM", time.Now())
	drain(client)
	target.X, target.Y, target.Protected = 142, 42, false
	bullet := infiniteBullet{Owner: 999, ownerName: "DEPARTED", Color: 6, Kind: "cannon", X: 42, Y: 42}
	if a.advanceBullet(&bullet, 100, 0) || target.HP != 0 {
		t.Fatal("departed owner's shell did not hit")
	}
	a.broadcast()
	var packet infiniteSnapshot
	if err := json.Unmarshal(<-client.send, &packet); err != nil {
		t.Fatal(err)
	}
	if len(packet.Tanks) != 1 || packet.Tanks[0].KilledBy != "DEPARTED" || packet.Tanks[0].KilledByColor != tankColors[6] {
		t.Fatalf("missing authoritative killer metadata: %+v", packet.Tanks)
	}
}
