package main

import (
	"encoding/json"
	"os"
	"testing"
)

// The browser uses these same fixtures for its next-boss preview. Compare the
// equipment to actual grants, so a changed authoritative loadout cannot silently
// leave the preview describing gear the next boss will not receive.
func TestSurvival430BossPreviewMatchesAuthoritativeGrants(t *testing.T) {
	var fixtures []struct {
		Name          string   `json:"name"`
		Difficulty    string   `json:"difficulty"`
		BossName      string   `json:"bossName"`
		Wave          int      `json:"wave"`
		PickupRate    string   `json:"pickupRate"`
		Weapons       []string `json:"weapons"`
		ShieldCharges int      `json:"shieldCharges"`
		SpeedStacks   int      `json:"speedStacks"`
		Weapon        string   `json:"weapon"`
	}
	data, err := os.ReadFile("tests/survival-boss-fixtures.json")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) == 0 {
		t.Fatal("missing boss loadout parity fixtures")
	}
	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			g := newGame(430)
			g.Rules.PickupRate, g.Rules.Weapons = fixture.PickupRate, fixture.Weapons
			if survivalBossDifficulty(fixture.Wave) != fixture.Difficulty || survivalBossName(fixture.Wave) != fixture.BossName {
				t.Fatal("boss difficulty/name differs from browser preview")
			}
			boss := &Tank{Alive: true}
			g.survivalBossPower(boss, fixture.Wave)
			if boss.ShieldCharges != fixture.ShieldCharges || boss.SpeedStacks != fixture.SpeedStacks || boss.Power != fixture.Weapon {
				t.Fatalf("boss kit differs from browser preview: shield=%d speed=%d weapon=%q, want shield=%d speed=%d weapon=%q", boss.ShieldCharges, boss.SpeedStacks, boss.Power, fixture.ShieldCharges, fixture.SpeedStacks, fixture.Weapon)
			}
		})
	}
}
