package main

import (
	"database/sql"
	"time"
)

// Each local seat keeps its own primary score profile. The shared connection
// links live bodies, not ownership; a P2 key also works as P1 on another device.
func (s *infiniteServer) joinIndependentPublic(c *Client, msg infiniteMessage, now time.Time, connection infiniteConnection) (infiniteConnection, string) {
	a := s.public
	if err := s.persistPublicLocked(nil, nil); err != nil {
		return infiniteConnection{}, infinitePublicStoreBusy
	}
	primaryHash, _ := publicTokenHash(msg.PublicToken)
	localHash, _ := publicTokenHash(msg.LocalPublicToken)
	primaryProfile, primarySaved := s.publicProfiles[primaryHash]
	localProfile, localSaved := s.publicProfiles[localHash]
	useLocal := cleanCallsign(msg.LocalName) != "" || !msg.UpdateNames && msg.LocalPublicToken != ""
	a.mu.Lock()
	name := cleanName(msg.Name)
	if primarySaved && !msg.UpdateNames {
		name = a.publicEntries[primaryProfile.primary].Name
	}
	localName := cleanCallsign(msg.LocalName)
	if useLocal && localSaved && !msg.UpdateNames {
		localName = a.publicEntries[localProfile.primary].Name
	}
	existingSeats := 0
	for _, p := range a.pilots {
		if !p.Bot && (p.publicKey == primaryHash || useLocal && p.publicKey == localHash) {
			existingSeats++
		}
	}
	count := 1
	if useLocal {
		count++
	}
	reserved := 0
	if connection.seat != nil {
		reserved = s.publicPending[infiniteRoomPilot{connection.room, connection.seat}].seats
	}
	if a.players+s.publicPendingCount-reserved-existingSeats+count > infiniteCapacity {
		a.mu.Unlock()
		return infiniteConnection{}, "Public Infinity is full. Try again when enough pilots leave."
	}
	reservedIDs := [2]int{}
	for i := 0; i < count; i++ {
		a.nextID++
		reservedIDs[i] = a.nextID
	}
	seed, next := a.seed, a.nextID
	oldEntries := make(map[int]infinitePublicEntry)
	for _, id := range []int{primaryProfile.primary, primaryProfile.local, localProfile.primary} {
		if entry, ok := a.publicEntries[id]; ok {
			oldEntries[id] = entry
		}
	}
	a.mu.Unlock()
	requests := []accountSeatClaim{{token: msg.PublicToken, name: name}}
	if useLocal {
		requests = append(requests, accountSeatClaim{token: msg.LocalPublicToken, name: localName, newAccount: msg.LocalNewAccount, transferFrom: msg.PublicToken})
	}
	profiles := make(map[string]infinitePublicProfile)
	entries := make(map[int]infinitePublicEntry)
	var wanted [2]int
	migratedLocal := 0
	accounts, err := s.hub.callsigns.claimSeatAccounts(requests, func(tx *sql.Tx, accounts []claimedSeatAccount) error {
		for seat, account := range accounts {
			profile, exists := s.publicProfiles[account.hash]
			id := profile.primary
			if !exists {
				id = reservedIDs[seat]
			}
			if seat == 1 && account.fresh && primarySaved && primaryProfile.local != 0 {
				if _, ok := oldEntries[primaryProfile.local]; ok {
					id = primaryProfile.local
					migratedLocal = id
				}
			}
			entry, restored := oldEntries[id]
			if !restored {
				entry = infinitePublicEntry{infiniteLeader: infiniteLeader{ID: id, ColorIndex: (id - 1) % len(tankColors)}, listed: true}
			}
			entry.Name, entry.listed = account.name, true
			color := msg.ColorIndex
			if seat == 1 {
				color = msg.LocalColorIndex
			}
			if (msg.UpdateNames || !restored) && color != nil && validColorIndex(color) {
				entry.ColorIndex = *color
			}
			entries[id] = entry
			wanted[seat] = id
			profile.hash, profile.primary, profile.used = account.hash, id, now.Unix()
			profile.localEnabled = false
			profiles[account.hash] = profile
			if accounts[seat].migration != nil {
				accounts[seat].consumed = true
				if tx != nil {
					if _, err := tx.Exec("DELETE FROM online_seat_migrations WHERE new_hash=?", account.hash); err != nil {
						return err
					}
				}
			}
		}
		if migratedLocal != 0 {
			main := profiles[accounts[0].hash]
			main.local = 0
			main.localEnabled = false
			profiles[main.hash] = main
			key := canonicalCallsign(oldEntries[migratedLocal].Name)
			r := s.hub.callsigns
			if r.claims[key] == accounts[0].hash {
				if tx != nil {
					if _, err := tx.Exec("UPDATE online_callsigns SET owner_hash=? WHERE canonical_name=?", accounts[1].hash, key); err != nil {
						return err
					}
				}
				accounts[1].extraAliases = map[string]string{key: r.names[accounts[0].hash][key]}
			}
		}
		return writePublicRows(tx, entries, profiles, seed, next)
	})
	if err != nil {
		return infiniteConnection{}, publicJoinClaimError(c, err)
	}
	if len(accounts) > 1 && accounts[1].fresh {
		s.hub.mu.Lock()
		s.hub.expireLegacyLocalClaims(msg.PublicToken, nil)
		s.hub.mu.Unlock()
	}
	a.mu.Lock()
	for id, entry := range entries {
		a.publicEntries[id] = entry
		delete(a.publicPending, id)
	}
	a.publicArchiveDirty = true
	a.mu.Unlock()
	for _, profile := range profiles {
		s.indexPublicProfile(profile)
	}
	s.publicStoreInitialized = true
	s.publicSavedSeed = seed
	s.publicSavedNextID = next
	wantedIDs := map[int]bool{wanted[0]: true}
	if useLocal {
		wantedIDs[wanted[1]] = true
	}
	actors := make(map[int]*infinitePilot)
	a.mu.Lock()
	for _, pilot := range a.pilots {
		if wantedIDs[pilot.ID] && !pilot.Bot {
			actors[pilot.ID] = pilot
			entry := entries[pilot.ID]
			pilot.Name, pilot.Score, pilot.ColorIndex = entry.Name, entry.Score, entry.ColorIndex
		}
	}
	a.mu.Unlock()
	var remove []*infinitePilot
	detach := func(old infiniteConnection) {
		a.mu.Lock()
		old.pilot.client = nil
		old.pilot.local = nil
		old.pilot.clearControls()
		if old.local != nil {
			old.local.clearControls()
		}
		a.mu.Unlock()
		for _, pilot := range []*infinitePilot{old.pilot, old.local} {
			if pilot != nil && !wantedIDs[pilot.ID] {
				remove = append(remove, pilot)
			}
		}
	}
	for client, old := range s.connections {
		if old.arena != a || old.pilot == nil || !wantedIDs[old.pilot.ID] && (old.local == nil || !wantedIDs[old.local.ID]) {
			continue
		}
		seat := 0
		if old.local != nil && (wantedIDs[old.local.ID] && !wantedIDs[old.pilot.ID] || old.local.ID == migratedLocal) {
			seat = 1
		}
		detach(old)
		delete(s.connections, client)
		stopAccountTransport(client, map[string]any{"type": "error", "code": "session_replaced", "seat": seat, "message": "This tank was opened on another device. This connection has signed out."})
	}
	for key, reservation := range s.reservations {
		old := reservation.connection
		if old.arena == a && old.pilot != nil && (wantedIDs[old.pilot.ID] || old.local != nil && wantedIDs[old.local.ID]) {
			detach(old)
			delete(s.reservations, key)
		}
	}
	for _, pilot := range remove {
		a.remove(pilot)
	}
	a.mu.Lock()
	if a.maze == nil {
		a.maze = newInfiniteMaze(a.seed)
	}
	var pilots [2]*infinitePilot
	for seat, account := range accounts {
		entry := entries[wanted[seat]]
		pilot := actors[entry.ID]
		if pilot == nil {
			x, y := 0.0, 0.0
			if pilots[0] != nil {
				x, y = pilots[0].X, pilots[0].Y
			}
			pilot = a.addPilot(entry.Name, false, x, y, 1, 3)
			pilot.ID = entry.ID
			a.players++
			a.connected++
		} else if pilot.disconnected {
			a.connected++
		}
		pilot.Name, pilot.Score, pilot.ColorIndex = entry.Name, entry.Score, entry.ColorIndex
		pilot.publicToken, pilot.publicKey = account.token, account.hash
		pilot.disconnected = false
		pilot.local = nil
		pilot.client = nil
		pilot.party = infiniteRoom{}
		pilot.partyMember = 0
		pilot.clearControls()
		pilot.Ack, pilot.AckSteps = 0, 0
		pilot.inputAt, pilot.activeAt = now, now
		pilots[seat] = pilot
	}
	pilots[0].client = c
	pilots[0].local = pilots[1]
	if !a.welcome(c, pilots[0], pilots[1], connection.room.generation, primarySaved) {
		a.mu.Unlock()
		a.remove(pilots[0])
		return infiniteConnection{}, "Could not join Infinity."
	}
	a.mu.Unlock()
	connection.arena, connection.pilot, connection.local = a, pilots[0], pilots[1]
	s.connections[c] = connection
	if connection.seat != nil {
		s.dropPublicPending(infiniteRoomPilot{connection.room, connection.seat})
		member := uint64(0)
		if connection.localSeat != nil {
			member = connection.localSeat.Member
		}
		a.bindParty(connection.pilot, connection.local, connection.room, connection.seat.Member, member)
	}
	return connection, ""
}
