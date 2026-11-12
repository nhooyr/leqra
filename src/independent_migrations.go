package main

import (
	"database/sql"
	"time"
)

// Private room claims run under Hub.mu, which must never acquire server.mu.
// Their durable marker is completed here under server.mu before simulation or
// admission can give the old shared controller another authoritative action.
func (s *infiniteServer) applySeatMigrations() error {
	r := s.hub.callsigns
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.seatMigrations) == 0 {
		return nil
	}
	if err := s.persistPublicLocked(nil, nil); err != nil {
		return err
	}
	profiles := make(map[string]infinitePublicProfile)
	entries := make(map[int]infinitePublicEntry)
	aliases := make(map[string]string)
	claimedIDs := make(map[int]string)
	s.public.mu.Lock()
	for hash, migration := range r.seatMigrations {
		previous, ok := s.publicProfiles[migration.previous]
		if !ok || previous.local == 0 {
			continue
		}
		if _, exists := s.publicProfiles[hash]; exists {
			continue
		}
		entry, exists := s.public.publicEntries[previous.local]
		if !exists {
			continue
		}
		oldName := canonicalCallsign(entry.Name)
		if r.claims[oldName] == migration.previous {
			aliases[oldName] = hash
		}
		entry.Name = r.names[hash][migration.name]
		if entry.Name == "" {
			entry.Name = migration.name
		}
		entries[entry.ID] = entry
		claimedIDs[entry.ID] = hash
		profiles[hash] = infinitePublicProfile{hash: hash, primary: entry.ID, used: time.Now().Unix()}
		previous.local = 0
		previous.localEnabled = false
		profiles[migration.previous] = previous
	}
	seed, next := s.public.seed, s.public.nextID
	s.public.mu.Unlock()
	var tx *sql.Tx
	if r.db != nil {
		var err error
		tx, err = r.db.Begin()
		if err != nil {
			return err
		}
		defer tx.Rollback()
		for name, hash := range aliases {
			if _, err = tx.Exec("UPDATE online_callsigns SET owner_hash=? WHERE canonical_name=?", hash, name); err != nil {
				return err
			}
		}
		if err = writePublicRows(tx, entries, profiles, seed, next); err != nil {
			return err
		}
		if _, err = tx.Exec("DELETE FROM online_seat_migrations"); err != nil {
			return err
		}
		if err = tx.Commit(); err != nil {
			return err
		}
	}
	for name, hash := range aliases {
		old := r.claims[name]
		display := r.names[old][name]
		delete(r.names[old], name)
		r.names[hash][name] = display
		r.claims[name] = hash
	}
	clear(r.seatMigrations)
	s.public.mu.Lock()
	for id, entry := range entries {
		s.public.publicEntries[id] = entry
		delete(s.public.publicPending, id)
	}
	s.public.publicArchiveDirty = true
	s.public.mu.Unlock()
	for _, profile := range profiles {
		s.indexPublicProfile(profile)
	}
	for client, connection := range s.connections {
		if connection.arena != s.public || connection.local == nil {
			continue
		}
		if _, migrated := claimedIDs[connection.local.ID]; !migrated {
			continue
		}
		delete(s.connections, client)
		connection.arena.mu.Lock()
		connection.local.Name = entries[connection.local.ID].Name
		connection.pilot.client = nil
		connection.pilot.clearControls()
		connection.local.clearControls()
		connection.arena.mu.Unlock()
		s.retire(connection)
		stopAccountTransport(client, map[string]any{"type": "error", "code": "session_replaced", "seat": 1, "message": "P2 moved to an independent account on another device. This connection has signed out."})
	}
	for key, reservation := range s.reservations {
		if reservation.connection.arena == s.public && reservation.connection.local != nil {
			if _, ok := claimedIDs[reservation.connection.local.ID]; ok {
				s.expireReservation(key, reservation)
			}
		}
	}
	return nil
}
