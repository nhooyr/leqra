package main

import (
	"slices"
)

// Drop historical aliases at startup. The saved primary score chooses the
// current name. A legacy shared P2 retains its name only until its existing
// independent-account migration moves that score to the P2 key.
func (s *infiniteServer) normalizeCallsigns() error {
	r := s.hub.callsigns
	r.mu.Lock()
	defer r.mu.Unlock()
	for hash, names := range r.names {
		if len(names) == 1 {
			for _, name := range names {
				if profile, ok := s.publicProfiles[hash]; ok && (s.public.publicEntries[profile.primary].Name != name || profile.local != 0) {
					r.renameMu.Lock()
					r.renamed[hash] = name
					r.renameMu.Unlock()
				}
			}
			continue
		}
		if len(names) == 0 {
			continue
		}
		var keep []string
		seen := map[string]bool{}
		if profile, ok := s.publicProfiles[hash]; ok {
			for _, id := range []int{profile.primary, profile.local} {
				if entry, ok := s.public.publicEntries[id]; ok {
					key := canonicalCallsign(entry.Name)
					if name, ok := names[key]; ok && !seen[key] {
						keep = append(keep, name)
						seen[key] = true
					}
				}
			}
		}
		if len(keep) == 0 {
			for _, name := range names {
				keep = append(keep, name)
			}
			slices.Sort(keep)
			keep = keep[:1]
		}
		if r.db != nil {
			tx, err := r.db.Begin()
			if err != nil {
				return err
			}
			if _, err = tx.Exec("DELETE FROM online_callsigns WHERE owner_hash=?", hash); err == nil {
				for _, name := range keep {
					if _, err = tx.Exec("INSERT INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?)", canonicalCallsign(name), name, hash); err != nil {
						break
					}
				}
			}
			if err == nil {
				err = tx.Commit()
			}
			if err != nil {
				tx.Rollback()
				return err
			}
		}
		r.replaceNamesLocked(hash, keep)
	}
	return nil
}

// A callsign change follows the account into all private rooms. Drain this
// separate queue under Hub.mu; score persistence must not consume room updates.
func (h *Hub) syncAccountCallsignsLocked() {
	r := h.callsigns
	r.renameMu.Lock()
	renamed := r.roomRenamed
	r.roomRenamed = make(map[string]string)
	r.renameMu.Unlock()
	if len(renamed) == 0 {
		return
	}
	for _, room := range h.rooms {
		changed := false
		for _, player := range room.members() {
			if player.Kind == "local" && player.PublicToken == "" {
				controller := player.Controller
				if controller == nil {
					controller = room.member(player.Owner)
				}
				if controller != nil {
					hash, _ := publicTokenHash(controller.PublicToken)
					if renamed[hash] != "" {
						h.expirePlayer(room, player.ID)
						changed = true
					}
				}
				continue
			}
			if player.PublicToken == "" {
				continue
			}
			hash, valid := publicTokenHash(player.PublicToken)
			name := renamed[hash]
			if !valid || name == "" || player.Name == name {
				continue
			}
			player.Name = name
			if tank := room.tankFor(player); tank != nil {
				tank.Name = name
			}
			if room.Game.stats != nil && room.Game.matchReport == nil {
				if row := room.Game.stats.members[player]; row != nil {
					row.Name = name
				}
			}
			changed = true
		}
		if changed {
			h.broadcastRoom(room)
		}
	}
}

func (h *Hub) syncAccountCallsigns() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.syncAccountCallsignsLocked()
}
