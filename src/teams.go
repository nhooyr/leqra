package main

import (
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"
)

const maxTeamNameRunes = 24

func defaultTeamNames() []string { return []string{"Team 1", "Team 2", "Team 3", "Team 4"} }
func validateTeamNames(names []string) error {
	if names == nil {
		return nil
	} // Compatibility with older saved presets.
	if len(names) != 4 {
		return errors.New("Name all four teams.")
	}
	for _, value := range names {
		name := strings.TrimSpace(value)
		if !utf8.ValidString(name) || utf8.RuneCountInString(name) < 1 || utf8.RuneCountInString(name) > maxTeamNameRunes {
			return errors.New("Team names must contain 1–24 characters.")
		}
		visible := false
		for _, r := range value {
			if unicode.IsControl(r) || r == '\u2028' || r == '\u2029' {
				return errors.New("Team names must be on one line without control characters.")
			}
			if !unicode.IsSpace(r) && !unicode.Is(unicode.Cf, r) {
				visible = true
			}
		}
		if !visible {
			return errors.New("Team names cannot be empty or invisible.")
		}
	}
	return nil
}

// Copy slice fields so accepted room rules never alias a request or preset buffer.
func normalizedRules(r MatchRules) MatchRules {
	if r.Mode == "survival" {
		r.TeamMode = "teams"
	}
	r.Weapons = append([]string{}, r.Weapons...)
	names := defaultTeamNames()
	if len(r.TeamNames) == 4 {
		for i, name := range r.TeamNames {
			names[i] = strings.TrimSpace(name)
		}
	}
	r.TeamNames = names
	r.TeamColors = append([]int{}, r.TeamColors...)
	if len(r.TeamColors) != 4 {
		r.TeamColors = defaultTeamColors()
	}
	return r
}
