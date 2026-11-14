package main

import (
	"crypto/sha256"
	"errors"
	"time"
)

var errNewAccountKeyInvalid = errors.New("new account key must be valid and unused")

type onlineAccountRotation struct {
	PublicToken string `json:"publicToken"`
	onlineAccountInfo
}

func accountRevokedPacket() map[string]any {
	return map[string]any{"type": "error", "code": "account_key_revoked", "message": infiniteAccountKeyRevoked}
}

// The new key is generated and safely saved by the client before this request.
// A lost HTTP response can therefore be recovered by validating that candidate.
// Ownership, scores, and revocation become durable in a single transaction.
func (s *infiniteServer) rotateAccount(oldToken, newToken string) (onlineAccountRotation, error) {
	rotation, err := s.rotateAccountState(oldToken, newToken)
	rotation.onlineAccountInfo = accountPreview(rotation.onlineAccountInfo)
	return rotation, err
}

func (s *infiniteServer) rotateAccountState(oldToken, newToken string) (onlineAccountRotation, error) {
	oldHash, oldValid := publicTokenHash(oldToken)
	newHash, newValid := publicTokenHash(newToken)
	if !oldValid {
		return onlineAccountRotation{}, errOnlineOwnerInvalid
	}
	if !newValid || oldHash == newHash {
		return onlineAccountRotation{}, errNewAccountKeyInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return onlineAccountRotation{}, errAccountServerClosed
	}
	if err := s.applySeatMigrations(); err != nil {
		return onlineAccountRotation{}, err
	}
	h := s.hub
	h.mu.Lock()
	r := h.callsigns
	r.mu.Lock()
	unlock := func() { r.mu.Unlock(); h.mu.Unlock() }
	if r.revoked[oldHash] {
		unlock()
		return onlineAccountRotation{}, errOnlineOwnerRevoked
	}
	if !r.owners[oldHash] {
		unlock()
		return onlineAccountRotation{}, errOnlineOwnerInvalid
	}
	if r.owners[newHash] || r.revoked[newHash] {
		unlock()
		return onlineAccountRotation{}, errNewAccountKeyInvalid
	}
	// Capture every score already acknowledged by the simulation before moving
	// the profile. No transport or in-memory credential changes precede commit.
	if err := s.persistPublicLocked(nil, nil); err != nil {
		unlock()
		return onlineAccountRotation{}, err
	}
	if r.db != nil {
		tx, err := r.db.Begin()
		if err != nil {
			unlock()
			return onlineAccountRotation{}, err
		}
		for _, statement := range []struct {
			query string
			args  []any
		}{
			{"INSERT INTO online_owners(token_hash) VALUES(?)", []any{newHash}},
			{"UPDATE online_callsigns SET owner_hash=? WHERE owner_hash=?", []any{newHash, oldHash}},
			{"UPDATE infinity_profiles SET token_hash=? WHERE token_hash=?", []any{newHash, oldHash}},
			{"UPDATE online_seat_migrations SET previous_hash=? WHERE previous_hash=?", []any{newHash, oldHash}},
			{"UPDATE online_seat_migrations SET new_hash=? WHERE new_hash=?", []any{newHash, oldHash}},
			{"UPDATE online_generated_fresh SET token_hash=? WHERE token_hash=?", []any{newHash, oldHash}},
			{"INSERT INTO online_revoked(token_hash) VALUES(?)", []any{oldHash}},
			{"DELETE FROM online_owners WHERE token_hash=?", []any{oldHash}},
		} {
			if _, err = tx.Exec(statement.query, statement.args...); err != nil {
				_ = tx.Rollback()
				unlock()
				return onlineAccountRotation{}, err
			}
		}
		if err = tx.Commit(); err != nil {
			_ = tx.Rollback()
			unlock()
			return onlineAccountRotation{}, err
		}
	}
	migrations := make(map[string]seatAccountMigration, len(r.seatMigrations))
	for _, migration := range r.seatMigrations {
		if migration.previous == oldHash {
			migration.previous = newHash
		}
		if migration.next == oldHash {
			migration.next = newHash
		}
		migrations[migration.next] = migration
	}
	r.seatMigrations = migrations
	delete(r.owners, oldHash)
	if r.generatedFresh[oldHash] {
		delete(r.generatedFresh, oldHash)
		r.generatedFresh[newHash] = true
	}
	r.owners[newHash] = true
	r.revoked[oldHash] = true
	r.names[newHash] = r.names[oldHash]
	delete(r.names, oldHash)
	for key := range r.names[newHash] {
		r.claims[key] = newHash
	}
	if profile, exists := s.publicProfiles[oldHash]; exists {
		delete(s.publicProfiles, oldHash)
		delete(s.publicZeroProfiles, oldHash)
		profile.hash = newHash
		s.indexPublicProfile(profile)
	}
	// Revoke body authority before granting a reliable notice time to flush.
	// readLoop can hold an already-decoded connection copy, so removing it from
	// s.connections alone is insufficient: its arena controller must be cleared.
	var retired []infiniteConnection
	transports := make(map[*Client]int)
	for client, connection := range s.connections {
		if connection.pilot == nil || connection.pilot.publicKey != oldHash && (connection.local == nil || connection.local.publicKey != oldHash) {
			continue
		}
		connection.arena.mu.Lock()
		connection.pilot.client = nil
		connection.pilot.clearControls()
		if connection.local != nil {
			connection.local.clearControls()
		}
		connection.arena.mu.Unlock()
		delete(s.connections, client)
		retired = append(retired, connection)
		seat := 0
		if connection.pilot.publicKey != oldHash {
			seat = 1
		}
		transports[client] = seat
	}
	for key, reservation := range s.reservations {
		if reservation.connection.pilot != nil && (reservation.connection.pilot.publicKey == oldHash || reservation.connection.local != nil && reservation.connection.local.publicKey == oldHash) {
			delete(s.reservations, key)
			retired = append(retired, reservation.connection)
		}
	}
	for key := range s.publicPending {
		if key.seat.PublicToken == oldToken || func() bool {
			local := roomLocalController(key.room.room, key.seat)
			return local != nil && local.PublicToken == oldToken
		}() {
			s.dropPublicPending(key)
		}
	}
	for client, seat := range h.revokeAccountLocked(oldToken, time.Now()) {
		transports[client] = seat
	}
	unlock()
	for _, connection := range retired {
		s.retire(connection)
	}
	for client, seat := range transports {
		packet := accountRevokedPacket()
		packet["seat"] = seat
		stopAccountTransport(client, packet)
	}
	info, err := s.accountInfoLocked(newToken)
	if err != nil {
		// The new owner exists until this mutex is released; this is an internal
		// invariant rather than a recoverable post-commit storage operation.
		panic("rotated account missing from ownership registry")
	}
	return onlineAccountRotation{PublicToken: newToken, onlineAccountInfo: info}, nil
}

// Called with Hub.mu held, after the durable key rotation commits. Expire the
// old seats rather than rewriting their owner: a copied private room token must
// never be able to resume and learn the replacement account key.
func (h *Hub) revokeAccountLocked(token string, now time.Time) map[*Client]int {
	if h.revokedRoomTokens == nil {
		h.revokedRoomTokens = make(map[[32]byte]time.Time)
	}
	for key, until := range h.revokedRoomTokens {
		if !now.Before(until) {
			delete(h.revokedRoomTokens, key)
		}
	}
	type member struct {
		room *Room
		seat *Player
	}
	var members []member
	controllers := make(map[*Client]int)
	for _, room := range h.rooms {
		for _, player := range room.members() {
			if player.PublicToken != token {
				continue
			}
			members = append(members, member{room, player})
			if player.Kind == "local" {
				owner := player.Controller
				if owner == nil {
					owner = room.member(player.Owner)
				}
				if owner != nil && owner.Client != nil {
					if _, ok := controllers[owner.Client]; !ok {
						controllers[owner.Client] = 1
					}
					h.detachController(room, owner, now)
				}
			}
			if player.Client != nil {
				controllers[player.Client] = 0
			}
			if player.Token != "" {
				h.revokedRoomTokens[sha256.Sum256([]byte(player.Token))] = now.Add(reconnectGrace + kickNoticeTTL)
			}
		}
	}
	for client := range h.clients {
		if client.onlineOwnerToken == token {
			controllers[client] = 0
		}
	}
	for client := range controllers {
		client.accountRevoked = true
		client.onlineOwnerToken = ""
	}
	changed := make(map[*Room]bool)
	for _, m := range members {
		if m.room.contains(m.seat) {
			h.expirePlayer(m.room, m.seat.ID)
			changed[m.room] = true
		}
		m.seat.Token, m.seat.PublicToken = "", ""
	}
	for room := range changed {
		h.finishQueueForfeit(room)
		h.broadcastRoom(room)
		h.broadcastState(room)
	}
	return controllers
}
