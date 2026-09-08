package main

import (
	"testing"
	"time"
)

func TestAddBot433InheritsLastRosterBotAndDefaultsToNormal(t *testing.T) {
	h, clients, r := makeRoom(t, 1)
	host := clients[0]
	action(t, h, host, map[string]any{"type": "add", "kind": "bot"})
	if r.Players[1] == nil || r.Players[1].Difficulty != "normal" {
		t.Fatal("first bot must default to Normal")
	}
	action(t, h, host, map[string]any{"type": "configure", "target": 1, "member": r.Players[1].Member, "difficulty": "hard"})
	action(t, h, host, map[string]any{"type": "add", "kind": "local"})
	action(t, h, host, map[string]any{"type": "add", "kind": "bot"})
	if r.Players[3] == nil || r.Players[3].Difficulty != "hard" {
		t.Fatal("local P2 must not interrupt difficulty inheritance")
	}
	// The following edits are a later UI burst, outside the action-rate window.
	host.msgWindow = time.Now().Add(-2 * time.Second)
	action(t, h, host, map[string]any{"type": "kick", "target": 1, "member": r.Players[1].Member})
	action(t, h, host, map[string]any{"type": "configure", "target": 3, "member": r.Players[3].Member, "difficulty": "godlike"})
	action(t, h, host, map[string]any{"type": "add", "kind": "bot"})
	if r.Players[1] == nil || r.Players[1].Difficulty != "godlike" {
		t.Fatal("reused earlier seat must inherit the last roster bot")
	}
	action(t, h, host, map[string]any{"type": "configure", "target": 1, "member": r.Players[1].Member, "difficulty": "easy"})
	action(t, h, host, map[string]any{"type": "add", "kind": "bot"})
	if r.Players[4] == nil || r.Players[4].Difficulty != "easy" {
		t.Fatal("inheritance must follow the latest bot after its earlier seat is reused")
	}
}

func TestAddBot433AcceptedEditWinsWhileExplicitDifficultyIsPreserved(t *testing.T) {
	h, clients, r := makeRoom(t, 1)
	host := clients[0]
	action(t, h, host, map[string]any{"type": "add", "kind": "bot", "difficulty": "easy"})
	// The browser can still display Chill while these ordered messages arrive.
	action(t, h, host, map[string]any{"type": "configure", "target": 1, "member": r.Players[1].Member, "difficulty": "godlike"})
	action(t, h, host, map[string]any{"type": "add", "kind": "bot"})
	if r.Players[2] == nil || r.Players[2].Difficulty != "godlike" {
		t.Fatal("Add Bot ignored the preceding authoritative edit")
	}
	action(t, h, host, map[string]any{"type": "add", "kind": "bot", "difficulty": "normal"})
	if r.Players[3] == nil || r.Players[3].Difficulty != "normal" {
		t.Fatal("explicit valid protocol difficulty was overridden")
	}
	action(t, h, host, map[string]any{"type": "add", "kind": "bot", "difficulty": "impossible"})
	if r.Players[4] != nil || !hasError(host, "bad_difficulty") {
		t.Fatal("invalid explicit difficulty must remain rejected")
	}
}
