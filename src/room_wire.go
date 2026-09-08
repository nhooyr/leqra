package main

// Match encoding/json's lexicographic map-key order in roomMessage, including
// optional false rematch votes and explicit color index zero. These public-only
// records avoid per-field map allocation/sorting on each room broadcast.
type roomMemberWire struct {
	Away       bool   `json:"away"`
	Color      string `json:"color"`
	ColorIndex *int   `json:"colorIndex,omitempty"`
	Connected  bool   `json:"connected"`
	Difficulty string `json:"difficulty"`
	HasParty   bool   `json:"hasParty"`
	ID         int    `json:"id"`
	Kind       string `json:"kind"`
	Member     uint64 `json:"member"`
	Name       string `json:"name"`
	Owner      int    `json:"owner"`
	Ready      bool   `json:"ready"`
	Rematch    *bool  `json:"rematch,omitempty"`
	Score      int    `json:"score"`
	Spectating bool   `json:"spectating"`
	Team       int    `json:"team"`
}

type roomMetadataWire struct {
	AwayMatch      string           `json:"awayMatch"`
	CanRestartWave bool             `json:"canRestartWave"`
	CanStart       bool             `json:"canStart"`
	Code           string           `json:"code"`
	Host           int              `json:"host"`
	Matchmaking    any              `json:"matchmaking"`
	MaxPlayers     int              `json:"maxPlayers"`
	MaxSpectators  int              `json:"maxSpectators"`
	Phase          string           `json:"phase"`
	Players        []roomMemberWire `json:"players"`
	Queue          any              `json:"queue"`
	Rules          MatchRules       `json:"rules"`
	Sides          int              `json:"sides"`
	Spectators     []roomMemberWire `json:"spectators"`
	StartError     string           `json:"startError"`
	Type           string           `json:"type"`
}

func (h *Hub) roomWire(r *Room) roomMetadataWire {
	rules := r.Game.settings()
	players := make([]roomMemberWire, 0, maxTanks)
	viewers := make([]roomMemberWire, 0, len(r.Spectators))
	for _, p := range r.members() {
		score := 0
		if !p.Spectating {
			score = r.Game.Scores[p.ID]
		}
		connected := p.Client != nil
		if p.Kind == "bot" {
			connected = true
		}
		if p.Kind == "local" {
			owner := r.member(p.Owner)
			connected = owner != nil && owner.Client != nil
		}
		entry := roomMemberWire{ID: p.ID, Member: p.Member, Name: p.Name, Color: selectedColor(p.ID, p.Team, p.ColorIndex, rules), Connected: connected, Ready: !p.Spectating && (p.Ready || p.Kind == "bot" || p.Kind == "local"), Score: score, Kind: playerKind(p), Owner: p.Owner, Team: p.Team, Difficulty: p.Difficulty, Spectating: p.Spectating, Away: p.Away != nil, HasParty: p.Return != nil}
		if r.Match != nil && r.Game.Phase == "matchOver" && r.Match.Rematch != nil {
			vote := r.Match.Rematch[p.Member]
			entry.Rematch = &vote
		}
		if p.ColorIndex != nil && rules.TeamMode == "ffa" {
			// Copy the value: a later roster edit cannot mutate a prepared record.
			color := *p.ColorIndex
			entry.ColorIndex = &color
		}
		if p.Spectating {
			viewers = append(viewers, entry)
		} else {
			players = append(players, entry)
		}
	}
	return roomMetadataWire{Type: "room", Code: r.Code, Host: r.Host, Phase: r.Game.Phase, Players: players, Spectators: viewers, CanStart: canStart(r), CanRestartWave: r.canRestartSurvivalWave(), MaxPlayers: r.combatCapacity(), MaxSpectators: maxSpectators, Rules: rules, StartError: r.Game.lineupError(r.Players), Sides: availableSides(r.Players), Queue: h.queueView(r.Queue), Matchmaking: matchView(r), AwayMatch: r.awayMatchCode()}
}
