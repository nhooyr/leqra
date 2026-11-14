package main

import (
	"encoding/json"
	"fmt"
	"math"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDumbDifficultyIsSelectableWithoutChangingPrivateDefaults(t *testing.T) {
	if !validDifficulty("dumb") || validDifficulty("Dumb") || tuneBot("dumb") != (botTuning{60, 1.8, .9, 1.8, .6, 0, false, false}) {
		t.Fatal("Dumb tier is missing its deliberately limited abilities")
	}
	rules := defaultRules()
	if rules.InfinityBotDifficulty != "normal" || infiniteBotLevel("") != infiniteBotLevel("normal") {
		t.Fatal("new public difficulty changed private/local defaults")
	}
	rules.InfinityBotDifficulty = "dumb"
	if err := validateRules(rules); err != nil {
		t.Fatal(err)
	}
	if err := validPresetRoster([]SeatSpec{{Kind: "human", Name: "Pilot"}, {Kind: "bot", Name: "Dumb", Difficulty: "dumb"}}); err != nil {
		t.Fatal(err)
	}
	h, clients, room := makeRoom(t, 1)
	action(t, h, clients[0], map[string]any{"type": "add", "kind": "bot", "name": "Dumb", "difficulty": "dumb"})
	if room.Players[1] == nil || room.Players[1].Difficulty != "dumb" {
		t.Fatal("server rejected a selectable Dumb bot", drain(clients[0]))
	}
}

func TestDumbFiniteBotHesitatesAndKeepsRapidReactionDelay(t *testing.T) {
	g := battle(2)
	bot := g.Tanks[0]
	bot.Bot, bot.Difficulty = true, "dumb"
	g.botControl(bot, tickDT)
	if bot.AI.Shot < 1.7 {
		t.Fatal("Dumb bot fired immediately after spawning")
	}
	attacks, hesitations, inaccurate := 0, 0, 0
	for range 120 {
		bot.X, bot.Y, bot.Angle = 90, 210, 0
		bot.AI.Think, bot.AI.Shot = 0, 100
		g.botControl(bot, tickDT)
		if bot.AI.HasAim {
			attacks++
			if math.Abs(bot.AI.Aim) > .15 {
				inaccurate++
			}
		} else {
			hesitations++
		}
	}
	if attacks < 30 || hesitations < 20 || inaccurate < 20 {
		t.Fatalf("Dumb bot lacked hesitant/inaccurate decisions: attacks=%d skips=%d inaccurate=%d", attacks, hesitations, inaccurate)
	}
	for _, tier := range []string{"dumb", "normal"} {
		g = battle(2)
		bot = g.Tanks[0]
		bot.Bot, bot.Difficulty, bot.Power, bot.PowerTime, bot.MachineRounds = true, tier, "rapid", 15, 50
		bot.AI = &BotState{Think: 100, HasAim: true, Aim: 0, Goal: -1, Target: 1, LastX: bot.X, LastY: bot.Y}
		g.botControl(bot, tickDT)
		if len(g.Bullets) == 0 {
			t.Fatal("rapid fixture did not fire")
		}
		if tier == "dumb" && bot.AI.Shot != 1.8 || tier == "normal" && bot.AI.Shot != 0 {
			t.Fatal("Dumb bypassed its reaction delay, or Medium rapid fire changed", tier, bot.AI.Shot)
		}
	}
}

func dumbInfinityFixture(t *testing.T) (*infiniteArena, *infinitePilot, *infinitePilot) {
	t.Helper()
	a := newSeededInfiniteArena(37)
	human := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	bot := a.addPilot("Bot 1", true, 0, 0, 1, 3)
	bot.ambientNumber = 1
	bot.X, bot.Y, bot.Angle = 42, 42, 0
	human.X, human.Y, human.Protected = 70, 42, false
	if a.rayBlocked(bot.X, bot.Y, human.X-bot.X, human.Y-bot.Y, infiniteBulletRadius) {
		t.Fatal("single-cell fixture was blocked")
	}
	return a, bot, human
}

func TestDumbInfinityBotUsesStaleBadAimAndSlowTriggerPulses(t *testing.T) {
	a, bot, human := dumbInfinityFixture(t)
	fires, skips, attacks, inaccurate := 0, 0, 0, 0
	var lastShot uint64
	for tick := uint64(0); tick < 60*30; tick++ {
		a.tick = tick
		input := a.botInput(bot)
		if tick%54 == 0 {
			if bot.botHasAim {
				attacks++
				if math.Abs(bot.botAim) > .15 {
					inaccurate++
				}
			} else {
				skips++
			}
		}
		if input.Fire {
			if tick < 108 || fires > 0 && tick-lastShot < 108 {
				t.Fatal("Dumb trigger fired too early or too rapidly", tick, lastShot)
			}
			fires++
			lastShot = tick
		}
		if input.AimOnly {
			bot.Angle = math.Atan2(input.StickY, input.StickX)
		}
	}
	if fires < 3 || fires > 17 || skips < 4 || attacks < 8 || inaccurate < 5 {
		t.Fatalf("Dumb decisions were passive or precise: shots=%d skipped=%d attacks=%d inaccurate=%d", fires, skips, attacks, inaccurate)
	}
	for !bot.botHasAim {
		a.tick = bot.botThink
		a.botInput(bot)
	}
	aim := bot.botAim
	human.X, human.Y = 42, 70
	a.tick++
	input := a.botInput(bot)
	if !input.AimOnly || math.Abs(delta(math.Atan2(input.StickY, input.StickX), aim)) > 1e-9 {
		t.Fatal("Dumb bot perfectly tracked movement between think cycles")
	}
}

func TestPublicBotIdentitiesKeepTheirTierAcrossSpawnOpportunities(t *testing.T) {
	a := newSeededInfiniteArena(37)
	human := a.join(fakeClient(), "Human", time.Unix(0, 0))
	identities := map[string]*infinitePilot{}
	numbers := map[int]string{}
	var previous *infinitePilot
	for life := 1; life <= 128; life++ {
		if previous != nil {
			previous.X = human.X + 30*cellSize
		}
		a.nextBot = a.tick
		a.populate()
		bots := roamingBots(a)
		if len(bots) != 1 {
			t.Fatal("opportunity did not replace the retired encounter", len(bots))
		}
		bot := bots[0]
		want := "dumb"
		if life%64 == 0 {
			want = "godlike"
		} else if life%16 == 8 {
			want = "normal"
		}
		if infiniteBotTunings[bot.botLevel].name != want || a.publicBotLives != uint64(life) {
			t.Fatal("spawn opportunity changed public cadence", life, bot.Name, a.publicBotLives)
		}
		if old := identities[want]; old != nil {
			if bot != old || bot.Score != 23 {
				t.Fatal("matching tier did not reuse its identity and score", life, bot.Name)
			}
		} else {
			if other := numbers[bot.ambientNumber]; other != "" {
				t.Fatal("new tier reused another identity's number", want, other)
			}
			identities[want], numbers[bot.ambientNumber] = bot, want
			bot.Score = 23
		}
		for tier, identity := range identities {
			if infiniteBotTunings[identity.botLevel].name != tier {
				t.Fatal("parked identity changed tier")
			}
		}
		previous = bot
	}
	if len(identities) != 3 || a.nextID != 4 {
		t.Fatal("repeated opportunities allocated duplicate identities", len(identities), a.nextID)
	}
}

func TestPublicGodlikeNameUsesBotNamespaceThroughoutPresentation(t *testing.T) {
	a, bot, _ := dumbInfinityFixture(t)
	bot.ambientNumber, bot.Score, bot.botLevel = 1234, 23, infiniteBotLevel("godlike")
	a.startBotLife(bot)
	const name = "Bot 1234 - Godlike"
	if bot.Name != name || bot.wireTank(a.tick).Name != name || !reservedCallsign(name) {
		t.Fatal("Godlike name lost its identity", bot.Name)
	}
	leaders := a.leaderboard(nil)
	if len(leaders) == 0 || leaders[0].ID != bot.ID || leaders[0].Name != name || leaders[0].Score != 23 {
		t.Fatal("leaderboard lost Godlike identity", leaders)
	}
	if len(a.godlikeSpawns) != 1 || a.godlikeSpawns[0].Name != name {
		t.Fatal("spawn notice lost name", a.godlikeSpawns)
	}
	lives := a.publicBotLives
	a.startBotLife(bot)
	if bot.Name != name || bot.Score != 23 || a.publicBotLives != lives {
		t.Fatal("reset changed permanent identity or encounter cadence")
	}
}

func TestPublicDeadBotWaitsForMatchingTierOpportunity(t *testing.T) {
	a, bot, human := dumbInfinityFixture(t)
	bot.Score = 23
	a.eliminatePilot(bot, human.ID, human.Team, human.Name)
	deadline, serial := bot.respawn, bot.Spawn
	a.nextBot = math.MaxUint64
	a.tick = deadline - 1
	a.populate()
	if len(roamingBots(a)) != 1 || bot.HP != 0 {
		t.Fatal("corpse disappeared before its contact window ended")
	}
	a.tick = deadline
	a.populate()
	if len(roamingBots(a)) != 0 || len(a.inactiveBots) != 1 || bot.Score != 22 || human.Score != 1 || bot.Spawn != serial {
		t.Fatal("death did not park scored identity")
	}
	a.publicBotLives = 7
	a.nextBot = a.tick
	a.populate()
	if bot.HP != 0 || bot.botLevel != infiniteBotLevel("dumb") || len(roamingBots(a)) != 1 || roamingBots(a)[0] == bot {
		t.Fatal("Medium opportunity reused a Dumb identity")
	}
	a.nextBot = a.tick
	a.populate()
	if bot.HP == 0 || bot.Score != 22 || bot.Spawn != serial+1 || a.publicBotLives != 9 {
		t.Fatal("Dumb opportunity lost original score or life", bot)
	}
}

func TestPublicGodlikeLimitScalesPer16ConnectedSeats(t *testing.T) {
	for _, test := range []struct{ connected, limit int }{{0, 0}, {1, 1}, {16, 1}, {17, 2}, {32, 2}, {33, 3}} {
		t.Run(fmt.Sprint(test.connected), func(t *testing.T) {
			a := newSeededInfiniteArena(37)
			a.connected = test.connected
			if a.publicGodlikeLimit() != test.limit {
				t.Fatal("incorrect 16-player cap", a.publicGodlikeLimit())
			}
			for i := 0; i < 4; i++ {
				a.publicBotLives = uint64((i+1)*64 - 1)
				bot := a.addPilot("Bot", true, 0, 0, 1, 3)
				if (bot.botLevel == infiniteBotLevel("godlike")) != (i < test.limit) {
					t.Fatal("scheduled encounter exceeded or underfilled population cap", i, test.limit)
				}
			}
			if a.livingPublicGodlikes(nil) != test.limit {
				t.Fatal("living encounter count differs from cap")
			}
		})
	}
}

func TestPublicGodlikeLimitShrinkParksExcessWithoutRetiering(t *testing.T) {
	a, ordinary, human := dumbInfinityFixture(t)
	a.connected = 33
	bosses := make([]*infinitePilot, 3)
	for i := range bosses {
		a.publicBotLives = uint64((i+1)*64 - 1)
		bosses[i] = a.addPilot("Bot", true, 0, 0, 1, 3)
		bosses[i].ambientNumber = i + 2
		bosses[i].publicBotName()
		bosses[i].Score = 20 + i
	}
	bosses[0].X, bosses[0].Y = human.X+30*cellSize, human.Y
	bosses[1].X, bosses[1].Y = human.X+cellSize, human.Y
	a.parkAmbientBot(len(a.pilots) - 1)
	lives := a.publicBotLives
	a.connected = 1
	a.trimRoamingBots()
	if a.livingPublicGodlikes(nil) != 1 || bosses[1].HP == 0 {
		t.Fatal("shrink did not retain visible encounter")
	}
	for _, p := range []*infinitePilot{bosses[0], bosses[2]} {
		if p.botLevel != infiniteBotLevel("godlike") || !strings.HasSuffix(p.Name, " - Godlike") || p.HP != 0 {
			t.Fatal("parked boss lost its tier or remained alive", p.Name)
		}
	}
	if bosses[0].Score != 20 || bosses[2].Score != 22 || a.publicBotLives != lives || ordinary.botLevel != infiniteBotLevel("dumb") {
		t.Fatal("population shrink changed points or cadence")
	}
	a.connected = 0
	a.trimRoamingBots()
	if a.livingPublicGodlikes(nil) != 0 || bosses[1].Score != 21 || bosses[1].HP != 0 || bosses[1].Name != "Bot 3 - Godlike" {
		t.Fatal("empty arena lost permanent boss identity")
	}
}

func TestPublicBotCounterAndPermanentTierSurviveRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	_, _, _ = savedPublicJoin(t, s, infiniteMessage{Name: "Pilot"})
	s.public.publicBotLives = 63
	bot := s.public.addPilot("Bot 1", true, 0, 0, 1, 3)
	bot.ambientNumber = 1
	bot.publicBotName()
	bot.Score = 12
	commitPublicFixture(t, s)
	id, seed, nextID := bot.ID, s.public.seed, s.public.nextID
	s.close()
	s = publicStoreFixture(t, path)
	defer s.close()
	if s.public.publicBotLives != 64 || len(s.public.inactiveBots) != 1 || s.public.seed != seed || s.public.nextID != nextID {
		t.Fatal("restart reset cadence, seed, or identities")
	}
	restored := s.public.inactiveBots[0]
	if restored.ID != id || restored.Score != 12 || restored.botLevel != infiniteBotLevel("godlike") || restored.Name != "Bot 1 - Godlike" || restored.HP != 0 {
		t.Fatal("restart changed permanent tier or score")
	}
	_, _, _ = savedPublicJoin(t, s, infiniteMessage{Name: "Other"})
	s.public.step(time.Now())
	if s.public.publicBotLives != 65 || restored.HP != 0 {
		t.Fatal("ordinary opportunity reactivated parked Godlike")
	}
	s.public.publicBotLives = 127
	s.public.nextBot = s.public.tick
	s.public.populate()
	if restored.HP == 0 || restored.Score != 12 || restored.ID != id || s.public.publicBotLives != 128 {
		t.Fatal("Godlike opportunity did not recover permanent identity")
	}
}

func TestInfinityDifficultyWireUsesActualBotTierOnly(t *testing.T) {
	a, bot, human := dumbInfinityFixture(t)
	bot.botLevel = infiniteBotLevel("godlike")
	for _, p := range []*infinitePilot{bot, human} {
		data, err := json.Marshal(p.wireTank(a.tick))
		if err != nil {
			t.Fatal(err)
		}
		if p.Bot && !strings.Contains(string(data), `"difficulty":"godlike"`) || !p.Bot && strings.Contains(string(data), `"difficulty"`) {
			t.Fatal("difficulty warning was omitted, fabricated, or attached to a human", string(data))
		}
	}
}
