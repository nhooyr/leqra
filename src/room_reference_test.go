package main

// Independent reference encoder for the typed room metadata tests.
func (h *Hub) roomMessage(r *Room) map[string]any {
	players, viewers := []map[string]any{}, []map[string]any{}
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
		entry := map[string]any{"id": p.ID, "member": p.Member, "name": p.Name, "color": selectedColor(p.ID, p.Team, p.ColorIndex, r.Game.settings()), "connected": connected, "ready": !p.Spectating && (p.Ready || p.Kind == "bot" || p.Kind == "local"), "score": score, "kind": playerKind(p), "owner": p.Owner, "team": p.Team, "difficulty": p.Difficulty, "spectating": p.Spectating, "away": p.Away != nil, "hasParty": p.Return != nil}
		if r.Match != nil && r.Game.Phase == "matchOver" && r.Match.Rematch != nil {
			entry["rematch"] = r.Match.Rematch[p.Member]
		}
		if p.ColorIndex != nil && r.Game.settings().TeamMode == "ffa" {
			entry["colorIndex"] = *p.ColorIndex
		}
		if p.Spectating {
			viewers = append(viewers, entry)
		} else {
			players = append(players, entry)
		}
	}
	return map[string]any{"type": "room", "code": r.Code, "host": r.Host, "phase": r.Game.Phase, "players": players, "spectators": viewers, "canStart": canStart(r), "canRestartWave": r.canRestartSurvivalWave(), "maxPlayers": r.combatCapacity(), "maxSpectators": maxSpectators, "rules": r.Game.settings(), "startError": r.Game.lineupError(r.Players), "sides": availableSides(r.Players), "queue": h.queueView(r.Queue), "matchmaking": matchView(r), "awayMatch": r.awayMatchCode()}
}
