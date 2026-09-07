package main

import "errors"

// Eight stable color identities. The dark-only client maps these canonical IDs to
// its curated neon palette; server physics never depend on CSS or arbitrary colors.
// -1 or omitted per-tank selection inherits the team color (or FFA seat default).

var tankColorIndex = func() map[string]int {
	m := make(map[string]int, len(tankColors))
	for i, color := range tankColors {
		m[color] = i
	}
	return m
}()

func validColorIndex(v *int) bool { return v == nil || (*v >= -1 && *v < 8) }
func copyColorIndex(v *int) *int {
	if v == nil {
		return nil
	}
	n := *v
	return &n
}
func defaultTeamColors() []int { return []int{0, 1, 2, 3} }
func validateTeamColors(v []int) error {
	if v == nil {
		return nil
	}
	if len(v) != 4 {
		return errors.New("Choose a color for each of the four teams.")
	}
	for _, n := range v {
		if n < 0 || n > 7 {
			return errors.New("Choose one of the eight palette colors.")
		}
	}
	return nil
}
func selectedColor(id, team int, selection *int, rules MatchRules) string {
	n := id % maxTanks
	if n < 0 {
		n = 0
	}
	// Numbered teams always use the room's team color. Individual paint is an
	// FFA-only cosmetic choice and can never override team identity.
	if team > 0 && team <= 4 {
		n = team - 1
		if len(rules.TeamColors) == 4 && rules.TeamColors[team-1] >= 0 && rules.TeamColors[team-1] < 8 {
			n = rules.TeamColors[team-1]
		}
		return tankColors[n]
	}
	if selection != nil && *selection >= 0 && *selection < 8 {
		n = *selection
	}
	return tankColors[n]
}
