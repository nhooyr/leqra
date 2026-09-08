package main

import "testing"

func TestPublish436OnlyBroadcastsCompleteImportedRoom(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth", "survival"} {
		for _, spectating := range []bool{false, true} {
			t.Run(mode+map[bool]string{false: "/pilot", true: "/spectator"}[spectating], func(t *testing.T) {
				h, c := newHub(8), fakeClient()
				rules := defaultRules()
				rules.Mode, rules.MapSize, rules.TeamMode = mode, "ultrawide", "teams"
				if mode == "survival" {
					rules.ScoreTarget = 15
				}
				roster := []SeatSpec{{Name: "HOST", Kind: "human", Team: 1, Spectating: spectating}, {Name: "P2", Kind: "local", Team: 1}, {Name: "BOT", Kind: "bot", Difficulty: "godlike", Team: 2}}
				action(t, h, c, map[string]any{"type": "publish", "code": "COMPLETE ROOM", "rules": rules, "roster": roster})
				if c.room == nil {
					t.Fatalf("publish failed: %v", drain(c))
				}
				rooms, states, welcomed := 0, 0, false
				for _, packet := range drain(c) {
					switch packet["type"] {
					case "welcome":
						welcomed = true
					case "room":
						rooms++
						if !welcomed {
							t.Fatal("room preceded identity")
						}
						settings := packet["rules"].(map[string]any)
						if settings["mode"] != mode || settings["mapSize"] != "ultrawide" {
							t.Fatalf("transient default rules: %v", settings)
						}
						want := 3
						if spectating {
							want = 2
						}
						if got := len(packet["players"].([]any)); got != want {
							t.Fatalf("partial roster %d != %d", got, want)
						}
					case "state":
						states++
						if rooms != 1 {
							t.Fatal("initial state must follow the complete room")
						}
						settings := packet["rules"].(map[string]any)
						if settings["mode"] != mode || settings["mapSize"] != "ultrawide" {
							t.Fatalf("transient default state: %v", settings)
						}
						if packet["generation"] != float64(0) || packet["world"] != nil {
							t.Fatal("publishing should not generate a new maze")
						}
					}
				}
				if rooms != 1 || states != 1 || !welcomed {
					t.Fatalf("wanted one complete welcome/room/state, rooms=%d states=%d welcome=%v", rooms, states, welcomed)
				}
			})
		}
	}
}
