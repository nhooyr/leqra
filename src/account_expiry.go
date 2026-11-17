package main

import (
	"database/sql"
	"errors"
	"time"
)

// Use the same UTC day and time next month, clamping to its final day when needed.
func accountExpiry(lastUsed time.Time) time.Time {
	used := lastUsed.UTC()
	lastDay := time.Date(used.Year(), used.Month()+2, 0, 0, 0, 0, 0, time.UTC).Day()
	return time.Date(used.Year(), used.Month()+1, min(used.Day(), lastDay), used.Hour(), used.Minute(), used.Second(), used.Nanosecond(), time.UTC)
}

func (r *onlineCallsignRegistry) callsignOwnerLocked(key string) (string, bool) {
	owner, exists := r.claims[key]
	return owner, exists && r.activeOwnerLocked(owner)
}

var errCallsignImmutable = errors.New("Changing callsign creates a separate account. Choose or create that callsign's account key.")

func (r *onlineCallsignRegistry) activeOwnerLocked(hash string) bool {
	return r.owners[hash] && !r.expired[hash] && (r.lastUsed[hash] == 0 || r.now().Before(accountExpiry(time.Unix(r.lastUsed[hash], 0))))
}
func (r *onlineCallsignRegistry) immutableNamesLocked(hash string, names []string) error {
	existing := r.names[hash]
	if len(existing) == 0 {
		if len(names) > 1 {
			return errCallsignImmutable
		}
		return nil
	}
	for _, name := range names {
		if _, ok := existing[canonicalCallsign(name)]; !ok {
			return errCallsignImmutable
		}
	}
	return nil
}

func (r *onlineCallsignRegistry) openAccountActivityLocked(db *sql.DB) error {
	// Old databases receive a full migration grace period exactly once.
	if _, err := db.Exec("INSERT OR IGNORE INTO online_account_activity(token_hash,last_used) SELECT token_hash,? FROM online_owners", r.now().Unix()); err != nil {
		return err
	}
	rows, err := db.Query("SELECT token_hash,last_used FROM online_account_activity")
	if err != nil {
		return err
	}
	for rows.Next() {
		var hash string
		var used int64
		if err = rows.Scan(&hash, &used); err != nil {
			break
		}
		r.lastUsed[hash] = used
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return err
	}
	rows, err = db.Query("SELECT token_hash FROM online_expired_accounts")
	if err != nil {
		return err
	}
	for rows.Next() {
		var hash string
		if err = rows.Scan(&hash); err != nil {
			break
		}
		r.expired[hash] = true
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	return err
}
func (r *onlineCallsignRegistry) writeAccountUseLocked(tx *sql.Tx, hash string) error {
	if tx == nil {
		return nil
	}
	_, err := tx.Exec("INSERT INTO online_account_activity(token_hash,last_used) VALUES(?,?) ON CONFLICT(token_hash) DO UPDATE SET last_used=excluded.last_used", hash, r.now().Unix())
	return err
}
func (r *onlineCallsignRegistry) touchAccountLocked(hash string) error {
	if !r.activeOwnerLocked(hash) {
		return errOnlineOwnerInvalid
	}
	now := r.now().Unix()
	if r.lastUsed[hash] == now {
		return nil
	}
	if r.db != nil {
		if _, err := r.db.Exec("UPDATE online_account_activity SET last_used=? WHERE token_hash=?", now, hash); err != nil {
			return err
		}
	}
	r.lastUsed[hash] = now
	return nil
}

// Delete ownership and persisted score together, then queue removal of live
// metadata. Expired keys remain tombstoned so they cannot recreate old scores.
func (r *onlineCallsignRegistry) expireAccountsLocked() error {
	var expired []string
	for hash := range r.owners {
		if !r.activeOwnerLocked(hash) {
			expired = append(expired, hash)
		}
	}
	return r.removeAccountsLocked(expired)
}

func (r *onlineCallsignRegistry) removeAccountsLocked(expired []string) error {
	if len(expired) == 0 {
		return nil
	}
	var tx *sql.Tx
	if r.db != nil {
		var err error
		tx, err = r.db.Begin()
		if err != nil {
			return err
		}
		defer tx.Rollback()
		for _, hash := range expired {
			var primary int
			var local sql.NullInt64
			err = tx.QueryRow("SELECT primary_id,local_id FROM infinity_profiles WHERE token_hash=?", hash).Scan(&primary, &local)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return err
			}
			if _, err = tx.Exec("DELETE FROM infinity_profiles WHERE token_hash=?", hash); err != nil {
				return err
			}
			if primary != 0 {
				if _, err = tx.Exec("DELETE FROM infinity_scores WHERE id=? OR id=?", primary, local.Int64); err != nil {
					return err
				}
			}
			for _, q := range []string{
				"DELETE FROM infinity_profiles WHERE token_hash=?",
				"DELETE FROM online_callsigns WHERE owner_hash=?",
				"DELETE FROM online_generated_fresh WHERE token_hash=?",
				"DELETE FROM online_account_activity WHERE token_hash=?",
				"DELETE FROM online_seat_migrations WHERE new_hash=? OR previous_hash=?",
			} {
				var args []any = []any{hash}
				if q == "DELETE FROM online_seat_migrations WHERE new_hash=? OR previous_hash=?" {
					args = append(args, hash)
				}
				if _, err = tx.Exec(q, args...); err != nil {
					return err
				}
			}
			if _, err = tx.Exec("INSERT OR IGNORE INTO online_expired_accounts(token_hash) VALUES(?)", hash); err != nil {
				return err
			}
			if _, err = tx.Exec("DELETE FROM online_owners WHERE token_hash=?", hash); err != nil {
				return err
			}
		}
		if err = tx.Commit(); err != nil {
			return err
		}
	}
	for _, hash := range expired {
		for key := range r.names[hash] {
			delete(r.claims, key)
		}
		delete(r.names, hash)
		delete(r.owners, hash)
		delete(r.lastUsed, hash)
		delete(r.generatedFresh, hash)
		r.expired[hash] = true
		r.expiryMu.Lock()
		r.expirationPending[hash] = true
		r.expiryMu.Unlock()
		for key, m := range r.seatMigrations {
			if m.next == hash || m.previous == hash {
				delete(r.seatMigrations, key)
			}
		}
	}
	return nil
}

func (s *infiniteServer) expireAccounts() error {
	r := s.hub.callsigns
	// Every connected gameplay session counts as use, even during long matches.
	hashes := map[string]bool{}
	for _, c := range s.connections {
		for _, p := range []*infinitePilot{c.pilot, c.local} {
			if p != nil && p.publicKey != "" {
				hashes[p.publicKey] = true
			}
		}
	}
	s.hub.mu.Lock()
	for _, room := range s.hub.rooms {
		for _, p := range room.members() {
			if p.PublicToken != "" && (p.Client != nil || p.Kind == "local" && func() bool {
				owner := p.Controller
				if owner == nil {
					owner = room.member(p.Owner)
				}
				return owner != nil && owner.Client != nil
			}()) {
				hash, _ := publicTokenHash(p.PublicToken)
				hashes[hash] = true
			}
		}
	}
	s.hub.mu.Unlock()
	r.mu.Lock()
	if r.now().Unix() >= r.nextActiveTouch {
		for hash := range hashes {
			if r.owners[hash] && !r.expired[hash] {
				if r.db != nil {
					if _, err := r.db.Exec("UPDATE online_account_activity SET last_used=? WHERE token_hash=?", r.now().Unix(), hash); err != nil {
						r.mu.Unlock()
						return err
					}
				}
				r.lastUsed[hash] = r.now().Unix()
			}
		}
		r.nextActiveTouch = r.now().Unix() + 60
	}
	err := r.expireAccountsLocked()
	if err != nil {
		r.mu.Unlock()
		return err
	}
	r.expiryMu.Lock()
	expired := r.expirationPending
	r.expirationPending = make(map[string]bool)
	r.expiryMu.Unlock()
	r.mu.Unlock()
	s.retireExpiredAccounts(expired, "This inactive account expired. Choose a callsign to start a new account.")
	return nil
}

// Caller holds server.mu. Score tombstones are durable before any transport or
// room authority changes; cleanup can therefore never resurrect released data.
func (s *infiniteServer) retireExpiredAccounts(expired map[string]bool, message string) {
	if len(expired) == 0 {
		return
	}
	s.hub.mu.Lock()
	for key := range s.publicPending {
		hash, _ := publicTokenHash(key.seat.PublicToken)
		local := roomLocalController(key.room.room, key.seat)
		localHash := ""
		if local != nil {
			localHash, _ = publicTokenHash(local.PublicToken)
		}
		if expired[hash] || expired[localHash] {
			s.dropPublicPending(key)
		}
	}
	for _, room := range s.hub.rooms {
		changed := false
		for _, p := range room.members() {
			hash, _ := publicTokenHash(p.PublicToken)
			if expired[hash] {
				if p.Kind == "local" {
					owner := p.Controller
					if owner == nil {
						owner = room.member(p.Owner)
					}
					if owner != nil && owner.Client != nil {
						controller := owner.Client
						s.hub.detachController(room, owner, time.Now())
						stopAccountTransport(controller, map[string]any{"type": "error", "code": "account_key_invalid", "seat": 1, "message": message})
					}
				}
				if p.Client != nil {
					p.Client.accountRevoked = true
					p.Client.onlineOwnerToken = ""
					stopAccountTransport(p.Client, map[string]any{"type": "error", "code": "account_key_invalid", "message": message})
				}
				s.hub.expirePlayer(room, p.ID)
				changed = true
			}
		}
		if changed {
			s.hub.broadcastRoom(room)
		}
	}
	s.hub.mu.Unlock()
	for client, c := range s.connections {
		if c.observer != nil && c.seat != nil {
			hash, _ := publicTokenHash(c.seat.PublicToken)
			if expired[hash] {
				delete(s.connections, client)
				s.retire(c)
				stopAccountTransport(client, map[string]any{"type": "error", "code": "account_key_invalid", "message": message})
				continue
			}
		}
		if c.pilot != nil && (expired[c.pilot.publicKey] || c.local != nil && expired[c.local.publicKey]) {
			delete(s.connections, client)
			s.retire(c)
			stopAccountTransport(client, map[string]any{"type": "error", "code": "account_key_invalid", "message": message})
		}
	}
	for key, c := range s.reservations {
		if c.connection.pilot != nil && (expired[c.connection.pilot.publicKey] || c.connection.local != nil && expired[c.connection.local.publicKey]) {
			s.expireReservation(key, c)
		}
	}
	s.public.mu.Lock()
	for hash := range expired {
		if p, ok := s.publicProfiles[hash]; ok {
			for _, id := range []int{p.primary, p.local} {
				delete(s.public.publicEntries, id)
				delete(s.public.publicPending, id)
				delete(s.publicScoreOwners, id)
			}
			delete(s.publicProfiles, hash)
			delete(s.publicZeroProfiles, hash)
		}
	}
	s.public.publicArchiveDirty = true
	s.public.mu.Unlock()
	return
}
