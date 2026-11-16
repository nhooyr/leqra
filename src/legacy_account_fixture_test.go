package main

import (
	"encoding/json"
	"testing"
)

// Historical shared-key fixtures must be seeded explicitly: production can
// resume/migrate these rows, but must never create another shared account.
func seedLegacyAccountFixture(t *testing.T, r *onlineCallsignRegistry, token string, names []string) (string, bool) {
	t.Helper()
	r.mu.Lock()
	defer r.mu.Unlock()
	var hash string
	if token == "" {
		var err error
		token, hash, err = newPublicToken()
		if err != nil {
			t.Fatal(err)
		}
	} else {
		var valid bool
		hash, valid = publicTokenHash(token)
		if !valid || !r.activeOwnerLocked(hash) {
			return token, false
		}
	}
	seen := map[string]bool{}
	for _, name := range names {
		key := canonicalCallsign(name)
		owner, claimed := r.callsignOwnerLocked(key)
		if key == "" || reservedCallsign(name) || seen[key] || claimed && owner != hash {
			return token, false
		}
		seen[key] = true
	}
	if r.db != nil {
		tx, err := r.db.Begin()
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback()
		if _, err = tx.Exec("INSERT OR IGNORE INTO online_owners(token_hash) VALUES(?)", hash); err != nil {
			t.Fatal(err)
		}
		if err = r.writeAccountUseLocked(tx, hash); err != nil {
			t.Fatal(err)
		}
		for _, name := range names {
			if _, err = tx.Exec("INSERT OR IGNORE INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?)", canonicalCallsign(name), cleanCallsign(name), hash); err != nil {
				t.Fatal(err)
			}
		}
		if err = tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
	r.owners[hash] = true
	r.lastUsed[hash] = r.now().Unix()
	if r.names[hash] == nil {
		r.names[hash] = map[string]string{}
	}
	for _, name := range names {
		key := canonicalCallsign(name)
		r.claims[key] = hash
		if r.names[hash][key] == "" {
			r.names[hash][key] = cleanCallsign(name)
		}
	}
	return token, true
}

func seedLegacyInfinityFixture(t *testing.T, s *infiniteServer, msg *infiniteMessage) {
	if msg.IndependentAccounts || msg.LocalPublicToken != "" || msg.Code != "" || msg.Resume || cleanCallsign(msg.LocalName) == "" {
		return
	}
	// A parked legacy P2 remains a real historical score even if its claim
	// was normalized away; only restore that exact saved secondary identity.
	hash, _ := publicTokenHash(msg.PublicToken)
	if profile, exists := s.publicProfiles[hash]; exists {
		if profile.local == 0 || canonicalCallsign(s.public.publicEntries[profile.local].Name) != canonicalCallsign(msg.LocalName) {
			return
		}
	}
	if token, ok := seedLegacyAccountFixture(t, s.hub.callsigns, msg.PublicToken, []string{cleanName(msg.Name), cleanCallsign(msg.LocalName)}); ok {
		msg.PublicToken = token
	}
}

func seedLegacyRoomAction(t *testing.T, h *Hub, c *Client, value any) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return
	}
	var msg clientMessage
	if json.Unmarshal(encoded, &msg) != nil || msg.IndependentAccounts || msg.LocalPublicToken != "" || c.independentAccounts {
		return
	}
	var names []string
	token := msg.PublicToken
	switch msg.Type {
	case "add":
		if msg.Kind != "local" || c.player == nil || c.room == nil || c.room.Host != c.player.ID {
			return
		}
		token = c.player.PublicToken
		name := cleanCallsign(msg.Name)
		if name == "" {
			name = "CO-PILOT"
		}
		names = append(roomControllerNames(c.room, c.player, nil, ""), name)
	case "publish", "preset":
		if len(msg.Roster) == 0 {
			return
		}
		if msg.Type == "preset" {
			if c.player == nil || c.room == nil || c.room.Host != c.player.ID {
				return
			}
			token = c.player.PublicToken
		}
		names = []string{cleanName(msg.Roster[0].Name)}
		for _, seat := range msg.Roster[1:] {
			if seat.Kind == "local" {
				names = append(names, cleanName(seat.Name))
			}
		}
	default:
		return
	}
	if len(names) < 2 {
		return
	}
	if token != "" {
		hash, _ := publicTokenHash(token)
		if _, ok := h.callsigns.names[hash][canonicalCallsign(names[0])]; !ok {
			return
		}
	}
	if seeded, ok := seedLegacyAccountFixture(t, h.callsigns, token, names); ok && msg.Type == "publish" && token == "" {
		c.onlineOwnerToken = seeded
	}
}
