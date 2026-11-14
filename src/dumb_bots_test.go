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
			t.Fatal("Dumb bypassed its reaction delay, or Normal rapid fire changed", tier, bot.AI.Shot)
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

func TestPublicGodlikeCadenceCountsRespawnsAndLimitsLivingBosses(t *testing.T) {
	a, bot, _ := dumbInfinityFixture(t)
	a.nextBot = math.MaxUint64
	for life := 2; life <= 64; life++ {
		bot.HP, bot.respawn = 0, a.tick+1
		a.step(time.Unix(0, 0))
		if a.publicBotLives != uint64(life) {
			t.Fatal("actual respawn did not advance bot life count", life, a.publicBotLives)
		}
		if life < 64 && bot.botLevel != infiniteBotLevel("dumb") {
			t.Fatal("public boss appeared before its rare life")
		}
	}
	if bot.botLevel != infiniteBotLevel("godlike") || bot.Name != "Godlike Bot 1" || bot.wireTank(a.tick).Difficulty != "godlike" {
		t.Fatal("64th life lacked a real, visibly marked Godlike bot")
	}
	other := a.addPilot("Bot 2", true, 0, 0, 1, 3)
	other.ambientNumber = 2
	a.publicBotLives = 127
	a.startBotLife(other)
	if other.botLevel != infiniteBotLevel("dumb") {
		t.Fatal("existing living Godlike allowed boss difficulty buildup")
	}
	// An offscreen pooled boss is still alive, and must not permit a duplicate.
	a.inactiveBots = append(a.inactiveBots, bot)
	for i, p := range a.pilots {
		if p == bot {
			a.pilots = append(a.pilots[:i], a.pilots[i+1:]...)
			break
		}
	}
	a.publicBotLives = 191
	a.startBotLife(other)
	if other.botLevel != infiniteBotLevel("dumb") {
		t.Fatal("pooled living boss was ignored")
	}
	bot.HP = 0
	a.startBotLife(bot)
	if bot.botLevel != infiniteBotLevel("dumb") || bot.Name != "Bot 1" || bot.wireTank(a.tick).Difficulty != "dumb" {
		t.Fatal("next ordinary life retained a stale Godlike warning")
	}
}

func TestPublicBotRelocationAndPoolKeepTierWithoutNewLives(t *testing.T) {
	a, bot, human := dumbInfinityFixture(t)
	a.publicBotLives = 63
	a.startBotLife(bot)
	if bot.Name != "Godlike Bot 1" {
		t.Fatal("fixture lacked boss")
	}
	bot.X, bot.Y = human.X+17*cellSize, human.Y
	think, shot, lives, spawn := bot.botThink, bot.botShot, a.publicBotLives, bot.Spawn
	a.tick = a.nextBot
	a.populate()
	if bot.Spawn != spawn+1 || bot.Name != "Godlike Bot 1" || bot.botLevel != infiniteBotLevel("godlike") || bot.botThink != think || bot.botShot != shot || a.publicBotLives != lives+1 {
		t.Fatal("relocation rerolled boss life, tier, or cadence")
	}
	// populate may add one brand-new ordinary bot, accounting for +1 above.
	a.join(fakeClient(), "Second", time.Unix(0, 0))
	fillRoamingBots(a)
	// Place this boss last so reducing the budget moves it into the pool while
	// one connected pilot still permits the encounter.
	for i, p := range a.pilots {
		if p == bot {
			a.pilots = append(append(a.pilots[:i], a.pilots[i+1:]...), bot)
			break
		}
	}
	lives = a.publicBotLives
	a.suspend(human)
	if len(a.inactiveBots) < 1 {
		t.Fatal("bot was not pooled")
	}
	if reason := a.resume(fakeClient(), human, 0, time.Unix(1, 0)); reason != "" {
		t.Fatal(reason)
	}
	for len(a.inactiveBots) > 0 {
		a.tick = a.nextBot
		a.populate()
	}
	if a.publicBotLives != lives || bot.Name != "Godlike Bot 1" || bot.botLevel != infiniteBotLevel("godlike") {
		t.Fatal("reactivating the pool counted a new life or changed the boss")
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

func TestPublicGodlikeLimitShrinkDowngradesExcessWithoutNewLives(t *testing.T) {
	a, ordinary, human := dumbInfinityFixture(t)
	a.connected = 33
	bosses := make([]*infinitePilot, 3)
	for i := range bosses {
		a.publicBotLives = uint64((i+1)*64 - 1)
		bosses[i] = a.addPilot("Bot", true, 0, 0, 1, 3)
		bosses[i].ambientNumber = i + 2
		bosses[i].publicBotName()
		bosses[i].Score = 20 + i
		bosses[i].botHasAim = true
	}
	bosses[0].X, bosses[0].Y = human.X+30*cellSize, human.Y
	bosses[1].X, bosses[1].Y = human.X+cellSize, human.Y
	pooled := bosses[2]
	a.pilots = a.pilots[:len(a.pilots)-1]
	a.inactiveBots = append(a.inactiveBots, pooled)
	lives, spawn, x, y := a.publicBotLives, bosses[0].Spawn, bosses[0].X, bosses[0].Y
	a.connected = 1
	a.trimRoamingBots()
	if a.livingPublicGodlikes(nil) != 1 || bosses[1].botLevel != infiniteBotLevel("godlike") {
		t.Fatal("population shrink did not keep the visible boss first")
	}
	for _, p := range []*infinitePilot{bosses[0], pooled} {
		if p.botLevel != infiniteBotLevel("dumb") || strings.HasPrefix(p.Name, "Godlike ") || p.botHasAim || p.botShot != a.tick+108 || p.HP != 1 {
			t.Fatal("excess boss did not become a fresh-thinking Dumb bot", p.Name, p.botHasAim)
		}
	}
	if bosses[0].Score != 20 || pooled.Score != 22 || bosses[0].Spawn != spawn || bosses[0].X != x || bosses[0].Y != y || a.publicBotLives != lives || ordinary.botLevel != infiniteBotLevel("dumb") {
		t.Fatal("downgrade changed position, score, spawn, or life count")
	}
	a.connected = 0
	a.trimRoamingBots()
	if a.livingPublicGodlikes(nil) != 0 || bosses[1].Score != 21 || bosses[1].HP != 1 || bosses[1].Name != "Bot 3" {
		t.Fatal("empty arena retained a boss or erased its score/body")
	}
}

func TestPublicBotCounterPersistsAndRestoredTiersDefaultToDumb(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	_, _, _ = savedPublicJoin(t, s, infiniteMessage{Name: "Pilot"})
	s.public.publicBotLives = 63
	bot := s.public.addPilot("Bot 1", true, 0, 0, 1, 3)
	bot.ambientNumber = 1
	bot.publicBotName()
	bot.Score = 12
	commitPublicFixture(t, s)
	id := bot.ID
	s.close()
	s = publicStoreFixture(t, path)
	if s.public.publicBotLives != 64 || len(s.public.inactiveBots) != 1 {
		t.Fatal("restart reset the rare encounter cadence")
	}
	restored := s.public.inactiveBots[0]
	if restored.ID != id || restored.Score != 12 || restored.botLevel != infiniteBotLevel("dumb") || restored.Name != "Bot 1" || restored.HP != 0 {
		t.Fatal("restart changed score or restored a stale living boss")
	}
	_, _, _ = savedPublicJoin(t, s, infiniteMessage{Name: "Other"})
	s.public.step(time.Now())
	if s.public.publicBotLives != 65 || restored.HP == 0 || restored.wireTank(s.public.tick).Difficulty != "dumb" {
		t.Fatal("restored dead bot did not start a fresh ordinary life")
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
