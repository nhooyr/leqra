package main

import (
	"errors"
	"math"
	"reflect"
	"time"
)

// Rules are room-owned, validated atomically, and immutable during a match.
// Never trust a browser to set objective scores, respawns, or pickup state.
type MatchRules struct {
	Mode           string   `json:"mode"`
	TeamMode       string   `json:"teamMode"`
	MapSize        string   `json:"mapSize"`
	ScoreTarget    int      `json:"scoreTarget"`
	TimeLimit      int      `json:"timeLimit"`
	RespawnSeconds int      `json:"respawnSeconds"`
	PickupRate     string   `json:"pickupRate"`
	Weapons        []string `json:"weapons"`
	FriendlyFire   bool     `json:"friendlyFire"`
	TeamNames      []string `json:"teamNames,omitempty"`
	TeamColors     []int    `json:"teamColors,omitempty"`
}

func defaultRules() MatchRules {
	return MatchRules{Mode: "elimination", TeamMode: "ffa", TeamNames: defaultTeamNames(), TeamColors: defaultTeamColors(), MapSize: "large", ScoreTarget: 5, TimeLimit: 75, RespawnSeconds: 3, PickupRate: "superfast", Weapons: append([]string{}, pickupTypes...)}
}
func (g *Game) settings() MatchRules {
	if g.Rules.Mode == "" {
		return defaultRules()
	}
	return g.Rules
}
func validateRules(r MatchRules) error {
	if err := validateTeamColors(r.TeamColors); err != nil {
		return err
	}
	if err := validateTeamNames(r.TeamNames); err != nil {
		return err
	}
	if r.Mode != "elimination" && r.Mode != "ctf" && r.Mode != "koth" && r.Mode != "survival" {
		return errors.New("Choose Elimination, Capture the Flag, King of the Hill, or Survival.")
	}
	if r.TeamMode != "teams" && r.TeamMode != "ffa" {
		return errors.New("Choose Teams or Free-for-all.")
	}
	if r.Mode == "survival" && r.TeamMode != "teams" {
		return errors.New("Survival requires Teams; every player joins the same squad.")
	}
	if r.Mode == "ctf" && r.TeamMode != "teams" {
		return errors.New("Capture the Flag requires two numbered teams, not Free-for-all.")
	}
	if r.MapSize != "compact" && r.MapSize != "standard" && r.MapSize != "large" && r.MapSize != "huge" && r.MapSize != "giant" && r.MapSize != "ultrawide" {
		return errors.New("Choose a valid map size.")
	}
	max := 20
	if r.Mode == "koth" {
		max = 300
	}
	if r.ScoreTarget < 1 || r.ScoreTarget > max {
		return errors.New("Score target is out of range (1–20, or 1–300 for Hill).")
	}
	if r.TimeLimit < 30 || r.TimeLimit > 600 {
		return errors.New("Time limit must be 30–600 seconds.")
	}
	if r.RespawnSeconds < 1 || r.RespawnSeconds > 10 {
		return errors.New("Respawn delay must be 1–10 seconds.")
	}
	if r.PickupRate != "superfast" && r.PickupRate != "fast" && r.PickupRate != "normal" && r.PickupRate != "slow" && r.PickupRate != "off" {
		return errors.New("Choose a valid pickup frequency.")
	}
	if len(r.Weapons) > len(pickupTypes) {
		return errors.New("Too many weapon types.")
	}
	seen := map[string]bool{}
	for _, w := range r.Weapons {
		valid := false
		for _, p := range pickupTypes {
			if p == w {
				valid = true
			}
		}
		if !valid || seen[w] {
			return errors.New("Unknown or repeated power-up.")
		}
		seen[w] = true
	}
	return nil
}
func (g *Game) mapDimensions() (int, int) {
	switch g.settings().MapSize {
	case "compact":
		return 7, 7
	case "large":
		return 12, 10
	case "huge":
		return 14, 12
	case "giant":
		return 16, 14
	case "ultrawide":
		return 24, 14
	default:
		return 9, 8
	}
}

// Pickup density is based on the actual maze, not a fixed room-wide cap.
func pickupCap(cols, rows int) int {
	if cols <= 0 || rows <= 0 {
		return 0
	}
	return int(math.Round(float64(cols*rows) / 9.8))
}

// One more starting pickup for each supported size tier (2 through 7).
func startingPickups(cols, rows int) int {
	area := cols * rows
	if area <= 0 {
		return 0
	}
	count := 2
	for _, previousArea := range []int{49, 72, 120, 168, 224} {
		if area > previousArea {
			count++
		}
	}
	return count
}

// Ground pickup lifetime scales with the maze pickup cap, with at least 30s
// through Large. Whole-second arithmetic keeps Giant cap 23 -> 61s.
func pickupLifetime(cols, rows int) float64 {
	cap := pickupCap(cols, rows)
	if cap <= 0 {
		return 0
	}
	lifetime := (cap * 8) / 3
	if cols*rows <= 12*10 {
		lifetime = max(30, lifetime)
	}
	return float64(lifetime)
}
func (g *Game) seedPickups() {
	for i := 0; i < startingPickups(g.World.Cols, g.World.Rows); i++ {
		g.spawnPower()
	}
}
func (g *Game) pickupInterval() (float64, float64) {
	switch g.settings().PickupRate {
	case "superfast":
		return 1, 2
	case "normal":
		return 4, 6
	case "slow":
		return 7, 10
	case "off":
		return math.Inf(1), math.Inf(1)
	default:
		return 2, 3.5
	}
}
func (g *Game) pickupDelay() float64 { lo, _ := g.pickupInterval(); return lo }
func (g *Game) objectiveMode() bool  { return g.settings().Mode == "ctf" || g.settings().Mode == "koth" }
func (g *Game) lineupError(ps [maxTanks]*Player) string {
	if g.survivalMode() {
		return g.survivalLineupError(ps)
	}
	if availableSides(ps) < 2 {
		return "Choose at least two opposing sides."
	}
	if g.settings().Mode == "ctf" {
		teams := map[int]bool{}
		for id, p := range ps {
			if p != nil && participantAvailable(ps, id) {
				if p.Team < 1 || p.Team > 2 {
					return "Capture the Flag uses Team 1 and Team 2; assign every participant."
				}
				teams[p.Team] = true
			}
		}
		if len(teams) != 2 {
			return "Capture the Flag needs exactly two numbered teams."
		}
	}
	return ""
}

func activeTeamCount(rules MatchRules) int {
	if rules.Mode == "survival" {
		return 1
	}
	if rules.TeamMode == "ffa" {
		return 0
	}
	if rules.Mode == "ctf" {
		return 2
	}
	return 4
}

// Rebalance only when enabling teams or changing the available team count.
// Ordinary edits preserve the host's manual assignments.
func balanceRoomTeams(r *Room) {
	count := activeTeamCount(r.Game.settings())
	n := 0
	for _, p := range r.Players {
		if p == nil {
			continue
		}
		p.Team = 0
		if count > 0 {
			p.Team = 1 + n%count
		}
		p.ColorIndex = nil
		n++
	}
}

func applyFormat(r *Room) {
	count := activeTeamCount(r.Game.settings())
	// Migrate old CTF presets/imports that used arbitrary numbered sides.
	if count == 2 {
		for _, p := range r.Players {
			if p != nil && (p.Team < 1 || p.Team > count) {
				balanceRoomTeams(r)
				break
			}
		}
	}
	for _, p := range r.members() {
		if count == 0 {
			p.Team = 0
		} else {
			// Team paint is authoritative. Do not retain a hidden FFA override that
			// could unexpectedly reappear after switching formats later.
			p.ColorIndex = nil
			if p.Team < 1 || p.Team > count {
				p.Team = joinTeam(r)
			}
		}
	}
}
func (h *Hub) setRules(c *Client, m clientMessage, now time.Time) {
	r, ok := h.editableHost(c, "rules")
	if !ok {
		return
	}
	fail := func(code, text string) { v := roomError(code, text); v["action"] = "rules"; c.enqueue(v) }
	if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		fail("match_active", "End the match before changing its rules.")
		return
	}
	if m.Rules == nil {
		fail("bad_rules", "Send the complete match rules.")
		return
	}
	rules := *m.Rules
	if err := validateRules(rules); err != nil {
		fail("bad_rules", err.Error())
		return
	}
	if rules.Mode == "survival" && participantCount(r.Players) > survivalMaxPlayers {
		fail("survival_full", "Survival supports up to four allied tanks. Remove extra tanks or move players to Spectators first.")
		return
	}
	previousTeamCount := activeTeamCount(r.Game.settings())
	nextRules := normalizedRules(rules)
	if !reflect.DeepEqual(r.Game.settings(), nextRules) {
		r.Game.survivalCheckpoint = nil
	}
	r.Game.Rules = nextRules
	r.Game.Clock = float64(rules.TimeLimit)
	if rules.TeamMode == "teams" && previousTeamCount != activeTeamCount(rules) {
		balanceRoomTeams(r)
	}
	applyFormat(r)
	resetReady(r)
	r.LastAction = now
	h.broadcastRoom(r)
}

// Saved rosters never contain remote people or credentials. Applying a preset
// online is atomic and only permitted while the host is the only controller.
func (h *Hub) applyPreset(c *Client, m clientMessage, now time.Time) {
	r, ok := h.editableHost(c, "preset")
	if !ok {
		return
	}
	fail := func(code, text string) { v := roomError(code, text); v["action"] = "preset"; c.enqueue(v) }
	if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		fail("match_active", "End the match before loading a preset.")
		return
	}
	for _, p := range r.members() {
		if p.ID != r.Host && p.Kind != "local" && p.Kind != "bot" {
			fail("guests_present", "Presets cannot replace online guests. Edit the rules or roster individually.")
			return
		}
	}
	if len(r.Spectators) > 0 {
		fail("spectator_preset", "Presets cannot replace spectator roles. Return local spectators to play and let online spectators leave before loading a preset.")
		return
	}
	if m.Rules == nil {
		fail("bad_rules", "Preset rules are required.")
		return
	}
	if err := validateRules(*m.Rules); err != nil {
		fail("bad_rules", err.Error())
		return
	}
	if err := validPresetRoster(m.Roster); err != nil {
		fail("bad_roster", err.Error())
		return
	}
	if m.Rules.Mode == "survival" && len(m.Roster) > survivalMaxPlayers {
		fail("survival_full", "Survival presets support up to four allied tanks.")
		return
	}
	for _, p := range r.members() {
		if p.ID != r.Host {
			h.expirePlayer(r, p.ID)
		}
	}
	host := r.Players[r.Host]
	host.Team = m.Roster[0].Team
	host.ColorIndex = copyColorIndex(m.Roster[0].ColorIndex)
	host.Name = cleanName(m.Roster[0].Name)
	for _, s := range m.Roster[1:] {
		id := 0
		for r.Players[id] != nil {
			id++
		}
		r.NextMember++
		r.Players[id] = &Player{ID: id, Member: r.NextMember, Kind: s.Kind, Name: cleanName(s.Name), Team: s.Team, ColorIndex: copyColorIndex(s.ColorIndex), Owner: r.Host, Controller: c.player, Difficulty: s.Difficulty, InputAt: now}
	}
	r.Game.Rules = normalizedRules(*m.Rules)
	r.Game.Clock = float64(m.Rules.TimeLimit)
	applyFormat(r)
	r.Game.Scores = [maxTanks]int{}
	r.Game.Tanks = [maxTanks]*Tank{}
	r.Game.Bullets = []*Bullet{}
	r.Game.Pickups = []*Pickup{}
	r.Game.Objectives = nil
	r.Game.survivalCheckpoint = nil
	r.Game.Phase = "lobby"
	resetReady(r)
	r.LastAction = now
	h.broadcastRoom(r)
	h.sendState(c, r)
}
func validPresetRoster(roster []SeatSpec) error {
	if len(roster) < 1 || len(roster) > maxTanks {
		return errors.New("Presets support 1–8 local participants.")
	}
	local := 0
	for i, s := range roster {
		if cleanCallsign(s.Name) == "" || s.Team < 0 || s.Team > 4 || !validColorIndex(s.ColorIndex) {
			return errors.New("Invalid preset name or team.")
		}
		if i == 0 {
			if s.Kind != "human" {
				return errors.New("The first preset seat must be the host.")
			}
		} else if s.Kind == "local" {
			local++
		} else if s.Kind != "bot" {
			return errors.New("Online guests cannot be stored in presets.")
		}
		if s.Kind == "bot" && !validDifficulty(s.Difficulty) {
			return errors.New("Invalid bot difficulty.")
		}
	}
	if local > 1 {
		return errors.New("Only one secondary local player is supported.")
	}
	return nil
}

// Empty teams are eligible too. Spectators never consume a tank position.
func joinTeam(r *Room) int {
	count := activeTeamCount(r.Game.settings())
	if count == 0 {
		return 0
	}
	counts := [5]int{}
	for _, p := range r.Players {
		if p != nil && p.Team > 0 && p.Team <= count {
			counts[p.Team]++
		}
	}
	best := 1
	for t := 2; t <= count; t++ {
		if counts[t] < counts[best] {
			best = t
		}
	}
	return best
}
