package main

import (
	"cmp"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	mathrand "math/rand/v2"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const (
	infinitePublicResumeInvalid = "That saved public Infinity pilot is unavailable. Join again."
	infinitePublicStoreBusy     = "Public Infinity scores are temporarily unavailable. Reconnecting…"
	infiniteZeroProfiles        = 8192
)

type infinitePublicEntry struct {
	infiniteLeader
	ambient int
	listed  bool
}

type infinitePublicProfile struct {
	hash           string
	primary, local int
	used           int64
	localEnabled   bool
}

// Only the application main enables disk storage. Tests and embedded uses can
// retain the same authenticated public identities entirely in memory.
func (s *infiniteServer) openPublicStore(path string) error {
	if path == "" {
		return nil
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(absolute), 0700); err != nil {
		return err
	}
	f, err := os.OpenFile(absolute, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	if err = os.Chmod(absolute, 0600); err != nil {
		return err
	}
	db, err := sql.Open("sqlite", (&url.URL{Scheme: "file", Path: absolute}).String())
	if err != nil {
		return err
	}
	db.SetMaxOpenConns(1)
	fail := func(err error) error { _ = db.Close(); return fmt.Errorf("public Infinity data %s: %w", absolute, err) }
	for _, statement := range []string{
		"PRAGMA busy_timeout=5000", "PRAGMA locking_mode=EXCLUSIVE", "PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL", "PRAGMA foreign_keys=ON",
		`CREATE TABLE IF NOT EXISTS infinity_meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL) WITHOUT ROWID`,
		`CREATE TABLE IF NOT EXISTS infinity_scores (id INTEGER PRIMARY KEY CHECK(id>0), name TEXT NOT NULL, score INTEGER NOT NULL, bot INTEGER NOT NULL CHECK(bot IN (0,1)), color_index INTEGER NOT NULL, ambient INTEGER NOT NULL DEFAULT 0, listed INTEGER NOT NULL DEFAULT 1 CHECK(listed IN (0,1)))`,
		`CREATE INDEX IF NOT EXISTS infinity_rank ON infinity_scores(listed,score DESC,id)`,
		`CREATE TABLE IF NOT EXISTS infinity_profiles (token_hash TEXT PRIMARY KEY, primary_id INTEGER NOT NULL UNIQUE REFERENCES infinity_scores(id), local_id INTEGER UNIQUE REFERENCES infinity_scores(id), last_used INTEGER NOT NULL) WITHOUT ROWID`,
	} {
		if _, err = db.Exec(statement); err != nil {
			return fail(err)
		}
	}
	var schema int
	if err = db.QueryRow("PRAGMA user_version").Scan(&schema); err != nil {
		return fail(err)
	}
	if schema > 1 {
		return fail(fmt.Errorf("unsupported schema version %d", schema))
	}
	if _, err = db.Exec("PRAGMA user_version=1"); err != nil {
		return fail(err)
	}
	columns, err := db.Query("PRAGMA table_info(infinity_profiles)")
	if err != nil {
		return fail(err)
	}
	hasLocalEnabled := false
	for columns.Next() {
		var cid, notnull, primary int
		var name, kind string
		var fallback any
		if err = columns.Scan(&cid, &name, &kind, &notnull, &fallback, &primary); err != nil {
			break
		}
		hasLocalEnabled = hasLocalEnabled || name == "local_enabled"
	}
	if err == nil {
		err = columns.Err()
	}
	columns.Close()
	if err != nil {
		return fail(err)
	}
	if !hasLocalEnabled {
		if _, err = db.Exec("ALTER TABLE infinity_profiles ADD COLUMN local_enabled INTEGER NOT NULL DEFAULT 1 CHECK(local_enabled IN (0,1))"); err != nil {
			return fail(err)
		}
	}
	var check string
	if err = db.QueryRow("PRAGMA quick_check").Scan(&check); err != nil || check != "ok" {
		if err == nil {
			err = errors.New("SQLite integrity check failed")
		}
		return fail(err)
	}
	entries := make(map[int]infinitePublicEntry)
	rows, err := db.Query("SELECT id,name,score,bot,color_index,ambient,listed FROM infinity_scores")
	if err != nil {
		return fail(err)
	}
	for rows.Next() {
		var e infinitePublicEntry
		if err = rows.Scan(&e.ID, &e.Name, &e.Score, &e.Bot, &e.ColorIndex, &e.ambient, &e.listed); err != nil {
			break
		}
		if e.ID <= 0 || cleanCallsign(e.Name) != e.Name || e.Name == "" || e.ColorIndex < 0 || e.ColorIndex >= len(tankColors) || e.ambient < 0 || e.ambient > infiniteBotLimit {
			err = errors.New("invalid saved public ranking")
			break
		}
		entries[e.ID] = e
	}
	if err == nil {
		err = rows.Err()
	}
	_ = rows.Close()
	if err != nil {
		return fail(err)
	}
	profiles := make(map[string]infinitePublicProfile)
	rows, err = db.Query("SELECT token_hash,primary_id,COALESCE(local_id,0),last_used,local_enabled FROM infinity_profiles")
	if err != nil {
		return fail(err)
	}
	owners := make(map[int]bool)
	for rows.Next() {
		var p infinitePublicProfile
		if err = rows.Scan(&p.hash, &p.primary, &p.local, &p.used, &p.localEnabled); err != nil {
			break
		}
		p.localEnabled = p.local != 0 && p.localEnabled
		digest, decodeErr := hex.DecodeString(p.hash)
		if decodeErr != nil || len(digest) != sha256.Size || p.primary == p.local {
			err = errors.New("invalid saved public credential")
			break
		}
		for _, id := range []int{p.primary, p.local} {
			if id == 0 {
				continue
			}
			e, ok := entries[id]
			if !ok || e.Bot || owners[id] {
				err = errors.New("invalid saved public identity")
				break
			}
			owners[id] = true
		}
		if err != nil {
			break
		}
		profiles[p.hash] = p
	}
	if err == nil {
		err = rows.Err()
	}
	_ = rows.Close()
	if err != nil {
		return fail(err)
	}
	var seed int64
	err = db.QueryRow("SELECT value FROM infinity_meta WHERE key='seed'").Scan(&seed)
	if err != nil && err != sql.ErrNoRows {
		return fail(err)
	}
	if err == nil {
		if seed < 0 || seed > 1<<32-1 {
			return fail(errors.New("invalid public maze seed"))
		}
		s.public.seed = uint32(seed)
		s.public.maze = newInfiniteMaze(uint32(seed))
		s.public.random = mathrand.New(mathrand.NewPCG(uint64(seed), 1))
	}
	var nextID int
	err = db.QueryRow("SELECT value FROM infinity_meta WHERE key='next_id'").Scan(&nextID)
	if err != nil && err != sql.ErrNoRows {
		return fail(err)
	}
	if nextID < 0 {
		return fail(errors.New("invalid public identity counter"))
	}
	var botLives int64
	err = db.QueryRow("SELECT value FROM infinity_meta WHERE key='bot_lives'").Scan(&botLives)
	if err != nil && err != sql.ErrNoRows {
		return fail(err)
	}
	if botLives < 0 {
		return fail(errors.New("invalid public bot life counter"))
	}
	s.public.publicBotLives = uint64(botLives)
	s.public.publicEntries = entries
	s.public.publicArchiveDirty = true
	s.publicProfiles = profiles
	s.publicScoreOwners = make(map[int]string)
	s.publicZeroProfiles = make(map[string]bool)
	for _, profile := range profiles {
		s.indexPublicProfile(profile)
	}
	for id, e := range entries {
		nextID = max(nextID, id)
		if e.Bot {
			if len(s.public.inactiveBots) >= infiniteBotLimit {
				return fail(errors.New("too many saved roaming bots"))
			}
			p := &infinitePilot{infiniteTank: infiniteTank{ID: id, Name: e.Name, Score: e.Score, Bot: true, ColorIndex: e.ColorIndex}, ambientNumber: e.ambient, botLevel: infiniteBotLevel("dumb")}
			p.publicBotName()
			s.public.inactiveBots = append(s.public.inactiveBots, p)
		}
	}
	if err = s.hub.callsigns.open(db); err != nil {
		return fail(err)
	}
	s.public.nextID = nextID
	s.publicDB = db
	if err = s.applySeatMigrations(); err != nil {
		return fail(err)
	}
	if err = s.persistPublicLocked(nil, nil); err != nil {
		s.publicDB = nil
		return fail(err)
	}
	return nil
}

func publicTokenHash(token string) (string, bool) {
	if len(token) != 45 || !strings.HasPrefix(token, "p_") {
		return "", false
	}
	data, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(token, "p_"))
	if err != nil || len(data) != 32 || base64.RawURLEncoding.EncodeToString(data) != token[2:] {
		return "", false
	}
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:]), true
}

func newPublicToken() (string, string, error) {
	var bytes [32]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", "", err
	}
	token := "p_" + base64.RawURLEncoding.EncodeToString(bytes[:])
	hash, _ := publicTokenHash(token)
	return token, hash, nil
}

func publicJoinClaimError(c *Client, err error) string {
	var seat *seatAccountError
	if errors.As(err, &seat) {
		c.accountFailureSeat = &seat.seat
	}
	if errors.Is(err, errSameSeatAccount) || errors.Is(err, errNewAccountKeyInvalid) {
		return err.Error()
	}
	if errors.Is(err, errOnlineOwnerRevoked) {
		return infiniteAccountKeyRevoked
	}
	var conflict *callsignConflictError
	if errors.As(err, &conflict) {
		c.callsignConflicts = conflict.Conflicts
		return conflict.Error()
	}
	if errors.Is(err, errOnlineOwnerInvalid) {
		return infinitePublicResumeInvalid
	}
	if err.Error() == infiniteSessionActive {
		return infiniteSessionActive
	}
	log.Printf("public Infinity identity commit failed: %v", err)
	return infinitePublicStoreBusy
}

// Allocate the score identity on the server, and durably commit it before its
// private welcome can reveal the bearer. Names are presentation, never proof.
func (s *infiniteServer) createPublicIdentity(first infiniteSeat, local *infiniteSeat, now time.Time) (infiniteSeat, *infiniteSeat, error) {
	a := s.public
	hash, _ := publicTokenHash(first.publicToken)
	previous, returning := s.publicProfiles[hash]
	a.mu.Lock()
	if a.publicEntries == nil {
		a.publicEntries = make(map[int]infinitePublicEntry)
		a.publicArchiveDirty = true
	}
	a.commitBeforeBroadcast = true
	if returning {
		for _, p := range a.pilots {
			if !p.Bot && p.publicKey == hash {
				a.mu.Unlock()
				return first, local, errors.New(infiniteSessionActive)
			}
		}
	}
	makeEntry := func(seat infiniteSeat, primary bool) infinitePublicEntry {
		id := 0
		if returning {
			if primary {
				id = previous.primary
			} else {
				id = previous.local
			}
		}
		old, restoring := a.publicEntries[id]
		if !restoring {
			a.nextID++
			id = a.nextID
		}
		name := cleanCallsign(seat.name)
		if primary {
			name = cleanName(seat.name)
		} else if name == "" {
			name = "CO-PILOT"
		}
		color := (id - 1) % len(tankColors)
		if seat.colorIndex >= 0 {
			color = seat.colorIndex
		}
		entry := infinitePublicEntry{infiniteLeader: infiniteLeader{ID: id, Name: name, ColorIndex: color}, listed: true}
		if restoring {
			entry.Score = old.Score
		}
		return entry
	}
	e := makeEntry(first, true)
	first.saved = &e
	profile := infinitePublicProfile{primary: e.ID, used: now.Unix()}
	if returning {
		profile.local = previous.local
	}
	entries := map[int]infinitePublicEntry{e.ID: e}
	if local != nil {
		copy := *local
		e := makeEntry(copy, false)
		copy.saved = &e
		local = &copy
		profile.local = e.ID
		profile.localEnabled = true
		entries[e.ID] = e
	}
	seed, nextID := a.seed, a.nextID
	a.mu.Unlock()
	names := []string{e.Name}
	if local != nil {
		names = append(names, local.saved.Name)
	}
	token, err := s.hub.callsigns.claimWithCommit(first.publicToken, names, func(tx *sql.Tx, hash string) error {
		profile.hash = hash
		return writePublicRows(tx, entries, map[string]infinitePublicProfile{hash: profile}, seed, nextID)
	})
	if err != nil {
		return first, local, err
	}
	first.publicToken = token
	a.mu.Lock()
	for id, e := range entries {
		a.publicEntries[id] = e
	}
	a.publicArchiveDirty = true
	a.mu.Unlock()
	s.indexPublicProfile(profile)
	s.publicStoreInitialized = true
	s.publicSavedSeed = seed
	s.publicSavedNextID = nextID

	return first, local, nil
}

// Manual Play may adopt edited local names. Recovery deliberately does not.
func (s *infiniteServer) updatePublicNames(msg infiniteMessage, profile infinitePublicProfile) (infinitePublicProfile, error) {
	a := s.public
	a.mu.Lock()
	first := a.publicEntries[profile.primary]
	first.Name = cleanName(msg.Name)
	first.listed = true
	if msg.ColorIndex != nil && validColorIndex(msg.ColorIndex) && *msg.ColorIndex >= 0 {
		first.ColorIndex = *msg.ColorIndex
	}
	changes := map[int]infinitePublicEntry{first.ID: first}
	names := []string{first.Name}
	profile.localEnabled = cleanCallsign(msg.LocalName) != ""
	if profile.localEnabled {
		local, exists := a.publicEntries[profile.local]
		if !exists {
			a.nextID++
			local = infinitePublicEntry{infiniteLeader: infiniteLeader{ID: a.nextID, ColorIndex: (a.nextID - 1) % len(tankColors)}}
			profile.local = local.ID
		}
		local.Name = cleanCallsign(msg.LocalName)
		local.listed = true
		if msg.LocalColorIndex != nil && validColorIndex(msg.LocalColorIndex) && *msg.LocalColorIndex >= 0 {
			local.ColorIndex = *msg.LocalColorIndex
		}
		changes[local.ID] = local
		names = append(names, local.Name)
	}
	seed, nextID := a.seed, a.nextID
	a.mu.Unlock()
	_, err := s.hub.callsigns.claimWithCommit(msg.PublicToken, names, func(tx *sql.Tx, hash string) error {
		return writePublicRows(tx, changes, map[string]infinitePublicProfile{hash: profile}, seed, nextID)
	})
	if err != nil {
		return profile, err
	}
	a.mu.Lock()
	for id, e := range changes {
		a.publicEntries[id] = e
	}
	a.publicArchiveDirty = true
	a.mu.Unlock()
	s.indexPublicProfile(profile)
	s.publicSavedSeed = seed
	s.publicSavedNextID = nextID
	s.publicStoreInitialized = true
	return profile, nil
}

func stopSupersededPublic(c *Client) {
	stopAccountTransport(c, map[string]any{"type": "error", "code": "session_replaced", "message": "This pilot was opened on another device. This connection has signed out."})
}

func stopAccountTransport(c *Client, packet map[string]any) {
	if !c.enqueue(packet) {
		c.stop()
		return
	}
	// The old transport no longer controls a body. Give its reliable writer a
	// short opportunity to deliver the terminal event before closing the socket.
	go func() {
		timer := time.NewTimer(200 * time.Millisecond)
		defer timer.Stop()
		select {
		case <-timer.C:
			c.stop()
		case <-c.done:
		}
	}()
}

// The bearer authenticates precisely one saved pair. A valid bearer may replace
// its own half-open transport immediately, without recreating its live body.
func (s *infiniteServer) resumePublic(c *Client, msg infiniteMessage, now time.Time) (infiniteConnection, string) {
	hash, valid := publicTokenHash(msg.PublicToken)
	profile, exists := s.publicProfiles[hash]
	if !valid {
		return infiniteConnection{}, infinitePublicResumeInvalid
	}
	if s.hub.callsigns.revokedOwner(msg.PublicToken) {
		return infiniteConnection{}, infiniteAccountKeyRevoked
	}
	if !exists {
		if _, known := s.hub.callsigns.owner(msg.PublicToken); !known {
			return infiniteConnection{}, infinitePublicResumeInvalid
		}
		first := infiniteSeat{name: msg.Name, colorIndex: -1, publicToken: msg.PublicToken}
		var local *infiniteSeat
		if msg.ColorIndex != nil && validColorIndex(msg.ColorIndex) {
			first.colorIndex = *msg.ColorIndex
		}
		if cleanCallsign(msg.LocalName) != "" {
			local = &infiniteSeat{name: msg.LocalName, colorIndex: -1}
			if msg.LocalColorIndex != nil && validColorIndex(msg.LocalColorIndex) {
				local.colorIndex = *msg.LocalColorIndex
			}
		}
		seats := 1
		if local != nil {
			seats++
		}
		if s.public.players+s.publicPendingCount+seats > infiniteCapacity {
			return infiniteConnection{}, "Public Infinity is full. Try again when enough pilots leave."
		}
		var err error
		first, local, err = s.createPublicIdentity(first, local, now)
		if err != nil {
			return infiniteConnection{}, publicJoinClaimError(c, err)
		}
		first.resumed = true
		p, second := s.public.joinSeats(c, first, local, 0, now)
		if p == nil {
			return infiniteConnection{}, "Could not join Infinity."
		}
		conn := infiniteConnection{arena: s.public, pilot: p, local: second}
		s.connections[c] = conn
		return conn, ""
	}

	a := s.public
	var previous infiniteConnection
	var old *Client
	var reserved *infiniteRoomPilot
	for client, conn := range s.connections {
		if conn.arena == a && conn.pilot != nil && conn.pilot.publicKey == hash {
			previous = conn
			old = client
			break
		}
	}
	if previous.pilot == nil {
		for key, r := range s.reservations {
			if r.connection.arena == a && r.connection.pilot.publicKey == hash {
				previous = r.connection
				copy := key
				reserved = &copy
				break
			}
		}
	}
	seats := 1
	enabled := profile.localEnabled
	if msg.UpdateNames {
		enabled = cleanCallsign(msg.LocalName) != ""
	}
	if enabled {
		seats++
	}
	existingSeats := 0
	if previous.pilot != nil {
		existingSeats = 1
		if previous.pilot.local != nil {
			existingSeats++
		}
	}
	if a.players+s.publicPendingCount-existingSeats+seats > infiniteCapacity {
		return infiniteConnection{}, "Public Infinity is full. Try again when enough pilots leave."
	}
	profile.used = now.Unix()
	if err := s.persistPublicLocked(nil, map[string]infinitePublicProfile{hash: profile}); err != nil {
		s.publicStoreError(err)
		return infiniteConnection{}, infinitePublicStoreBusy
	}
	if msg.UpdateNames {
		var err error
		profile, err = s.updatePublicNames(msg, profile)
		if err != nil {
			return infiniteConnection{}, publicJoinClaimError(c, err)
		}
	}
	if previous.pilot != nil {
		p := previous.pilot
		if p.local != nil && !profile.localEnabled {
			a.removeLocal(p)
		}
		a.mu.Lock()
		if p.local == nil && profile.localEnabled {
			entry := a.publicEntries[profile.local]
			local := a.addPilot(entry.Name, false, p.X, p.Y, 1, 3)
			local.ID, local.Score, local.ColorIndex = entry.ID, entry.Score, entry.ColorIndex
			local.publicKey = hash
			local.disconnected = p.disconnected
			local.inputAt, local.activeAt = now, now
			p.local = local
			a.players++
			if !local.disconnected {
				a.connected++
			}
		}
		for _, seat := range []*infinitePilot{p, p.local} {
			if seat != nil {
				entry := a.publicEntries[seat.ID]
				seat.Name, seat.ColorIndex = entry.Name, entry.ColorIndex
			}
		}
		p.publicToken = msg.PublicToken
		if !a.welcome(c, p, p.local, 0, true) {
			a.mu.Unlock()
			return infiniteConnection{}, "Could not join Infinity."
		}
		for _, seat := range []*infinitePilot{p, p.local} {
			if seat != nil {
				if seat.disconnected {
					a.connected++
				}
				seat.disconnected = false
				seat.party = infiniteRoom{}
				seat.partyMember = 0
				seat.clearControls()
				seat.Ack, seat.AckSteps = 0, 0
				seat.inputAt, seat.activeAt = now, now
			}
		}
		p.client = c
		a.mu.Unlock()
		if old != nil {
			delete(s.connections, old)
			stopSupersededPublic(old)
		}
		if reserved != nil {
			delete(s.reservations, *reserved)
		}
		conn := infiniteConnection{arena: a, pilot: p, local: p.local}
		s.connections[c] = conn
		return conn, ""
	}
	a.mu.Lock()
	entry, ok := a.publicEntries[profile.primary]
	localEntry, localOK := a.publicEntries[profile.local]
	a.mu.Unlock()
	if !ok || profile.localEnabled && !localOK {
		return infiniteConnection{}, infinitePublicResumeInvalid
	}
	first := infiniteSeat{saved: &entry, publicToken: msg.PublicToken, resumed: true, colorIndex: -1}
	var local *infiniteSeat
	if profile.localEnabled {
		local = &infiniteSeat{saved: &localEntry, colorIndex: -1}
	}
	p, second := a.joinSeats(c, first, local, 0, now)
	if p == nil {
		return infiniteConnection{}, "Could not join Infinity."
	}
	conn := infiniteConnection{arena: a, pilot: p, local: second}
	s.connections[c] = conn
	return conn, ""
}

func infiniteEntry(p *infinitePilot) infinitePublicEntry {
	return infinitePublicEntry{infiniteLeader: infiniteLeader{ID: p.ID, Name: p.Name, Score: p.Score, Bot: p.Bot, Team: p.Team, ColorIndex: p.ColorIndex}, ambient: p.ambientNumber, listed: true}
}

// Capture only live/pending changes. The durable identity table is never scanned
// for a normal simulation tick, and no database operation holds arena.mu.
func (s *infiniteServer) persistPublicLocked(extra map[int]infinitePublicEntry, profiles map[string]infinitePublicProfile) error {
	a := s.public
	a.mu.Lock()
	if a.publicEntries == nil {
		a.publicEntries = make(map[int]infinitePublicEntry)
		a.publicArchiveDirty = true
	}
	a.commitBeforeBroadcast = true
	changes := make(map[int]infinitePublicEntry, len(a.publicPending)+len(extra))
	for id, e := range a.publicPending {
		changes[id] = e
	}
	for i, list := range [][]*infinitePilot{a.pilots, a.inactiveBots} {
		for _, p := range list {
			e := infiniteEntry(p)
			old, ok := a.publicEntries[e.ID]
			if i == 1 && ok {
				e.listed = old.listed
			}
			if !ok || old != e {
				changes[e.ID] = e
			}
		}
	}
	for id, e := range extra {
		changes[id] = e
	}
	seed, nextID, botLives := a.seed, a.nextID, a.publicBotLives
	a.mu.Unlock()
	if len(changes) == 0 && len(profiles) == 0 && s.publicStoreInitialized && seed == s.publicSavedSeed && nextID == s.publicSavedNextID && botLives == s.publicSavedBotLives {
		return nil
	}
	if s.publicDB != nil {
		tx, err := s.publicDB.Begin()
		if err != nil {
			return err
		}
		defer tx.Rollback()
		if err = writePublicRows(tx, changes, profiles, seed, nextID, botLives); err != nil {
			return err
		}
		if err = tx.Commit(); err != nil {
			return err
		}
	}

	a.mu.Lock()
	for id, e := range changes {
		if !a.publicActive[id] {
			a.publicArchiveDirty = true
		}
		a.publicEntries[id] = e
		delete(a.publicPending, id)
	}
	a.mu.Unlock()
	for _, p := range profiles {
		s.indexPublicProfile(p)
	}
	for id := range changes {
		if hash := s.publicScoreOwners[id]; hash != "" {
			s.refreshPublicZero(hash)
		}
	}
	s.publicStoreInitialized = true
	s.publicSavedSeed = seed
	s.publicSavedNextID = nextID
	s.publicSavedBotLives = botLives
	return nil
}

// Only zero-score candidates need periodic churn pruning. Meaningful profiles
// are indexed by score owner and never scanned as part of a simulation tick.
func (s *infiniteServer) indexPublicProfile(p infinitePublicProfile) {
	if s.publicScoreOwners == nil {
		s.publicScoreOwners = make(map[int]string)
	}
	if s.publicZeroProfiles == nil {
		s.publicZeroProfiles = make(map[string]bool)
	}
	s.publicProfiles[p.hash] = p
	s.publicScoreOwners[p.primary] = p.hash
	if p.local != 0 {
		s.publicScoreOwners[p.local] = p.hash
	}
	s.refreshPublicZero(p.hash)
}
func (s *infiniteServer) refreshPublicZero(hash string) {
	p, exists := s.publicProfiles[hash]
	if !exists {
		delete(s.publicZeroProfiles, hash)
		return
	}
	s.public.mu.Lock()
	zero := s.public.publicEntries[p.primary].Score == 0 && (p.local == 0 || s.public.publicEntries[p.local].Score == 0)
	s.public.mu.Unlock()
	if zero {
		s.publicZeroProfiles[hash] = true
	} else {
		delete(s.publicZeroProfiles, hash)
	}
}

func writePublicRows(tx *sql.Tx, changes map[int]infinitePublicEntry, profiles map[string]infinitePublicProfile, seed uint32, nextID int, botLives ...uint64) error {
	if tx == nil {
		return nil
	}
	for _, e := range changes {
		_, err := tx.Exec(`INSERT INTO infinity_scores(id,name,score,bot,color_index,ambient,listed) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,score=excluded.score,bot=excluded.bot,color_index=excluded.color_index,ambient=excluded.ambient,listed=excluded.listed`, e.ID, e.Name, e.Score, e.Bot, e.ColorIndex, e.ambient, e.listed)
		if err != nil {
			return err
		}
	}
	for _, p := range profiles {
		var local any
		if p.local != 0 {
			local = p.local
		}
		if _, err := tx.Exec(`INSERT INTO infinity_profiles(token_hash,primary_id,local_id,last_used,local_enabled) VALUES(?,?,?,?,?) ON CONFLICT(token_hash) DO UPDATE SET primary_id=excluded.primary_id,local_id=excluded.local_id,last_used=excluded.last_used,local_enabled=excluded.local_enabled`, p.hash, p.primary, local, p.used, p.localEnabled); err != nil {
			return err
		}
	}
	meta := map[string]any{"seed": seed, "next_id": nextID}
	if len(botLives) != 0 {
		meta["bot_lives"] = botLives[0]
	}
	for key, value := range meta {
		if _, err := tx.Exec(`INSERT INTO infinity_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value WHERE value<>excluded.value`, key, value); err != nil {
			return err
		}
	}
	return nil
}

func (a *infiniteArena) rememberPublicLocked() {
	if a.publicEntries == nil {
		return
	}
	if a.publicPending == nil {
		a.publicPending = make(map[int]infinitePublicEntry)
	}
	for i, list := range [][]*infinitePilot{a.pilots, a.inactiveBots} {
		for _, p := range list {
			e := infiniteEntry(p)
			old, ok := a.publicEntries[e.ID]
			if i == 1 && ok {
				e.listed = old.listed
			}
			if !ok || old != e {
				a.publicPending[e.ID] = e
			}
		}
	}
}

func compareInfiniteLeaders(a, b infiniteLeader) int {
	if n := cmp.Compare(b.Score, a.Score); n != 0 {
		return n
	}
	return cmp.Compare(a.ID, b.ID)
}

func (a *infiniteArena) publicLeader(p *infinitePilot) infiniteLeader {
	if e, ok := a.publicEntries[p.ID]; ok {
		return e.infiniteLeader
	}
	leader := infiniteEntry(p).infiniteLeader
	// HTTP readers may run while a newly spawned bot's first score is being
	// committed. Uncommitted points must not escape through the status endpoint.
	if a.commitBeforeBroadcast {
		leader.Score = 0
	}
	return leader
}

func (a *infiniteArena) publicRankedLeaders(entries []infiniteLeader) []infiniteLeader {
	changed := a.publicArchiveDirty || len(a.publicActive) != len(a.pilots)
	if !changed {
		for _, p := range a.pilots {
			if !a.publicActive[p.ID] {
				changed = true
				break
			}
		}
	}
	if changed {
		a.publicActive = make(map[int]bool, len(a.pilots))
		for _, p := range a.pilots {
			a.publicActive[p.ID] = true
		}
		a.publicArchive = a.publicArchive[:0]
		for id, e := range a.publicEntries {
			if e.listed && !a.publicActive[id] {
				a.publicArchive = append(a.publicArchive, e.infiniteLeader)
			}
		}
		slices.SortFunc(a.publicArchive, compareInfiniteLeaders)
		a.publicArchiveDirty = false
	}
	entries = entries[:0]
	entries = append(entries, a.publicArchive[:min(len(a.publicArchive), infiniteLeaderCount)]...)
	for _, p := range a.pilots {
		entries = append(entries, a.publicLeader(p))
	}
	slices.SortFunc(entries, compareInfiniteLeaders)
	return entries
}

func (a *infiniteArena) publicRank(p *infinitePilot) int {
	leader := a.publicLeader(p)
	before, _ := slices.BinarySearchFunc(a.publicArchive, leader, compareInfiniteLeaders)
	rank := before + 1
	for _, other := range a.pilots {
		if other != p && compareInfiniteLeaders(a.publicLeader(other), leader) < 0 {
			rank++
		}
	}
	return rank
}

func (s *infiniteServer) publicStoreError(err error) {
	if err != nil {
		log.Printf("public Infinity score commit failed: %v", err)
	}
}

// Reclaim only old zero-score credentials. Meaningful saved scores never expire.
func (s *infiniteServer) prunePublicProfiles(now time.Time) error {
	if len(s.publicZeroProfiles) <= infiniteZeroProfiles {
		return nil
	}
	active := make(map[string]bool)
	for _, c := range s.connections {
		if c.pilot != nil {
			active[c.pilot.publicKey] = true
			if c.local != nil {
				active[c.local.publicKey] = true
			}
		}
	}
	for _, r := range s.reservations {
		if r.connection.arena == s.public && r.connection.pilot != nil {
			active[r.connection.pilot.publicKey] = true
			if r.connection.local != nil {
				active[r.connection.local.publicKey] = true
			}
		}
	}
	var zero []infinitePublicProfile
	for hash := range s.publicZeroProfiles {
		p := s.publicProfiles[hash]
		if !active[hash] && s.public.publicEntries[p.primary].Score == 0 && (p.local == 0 || s.public.publicEntries[p.local].Score == 0) {
			zero = append(zero, p)
		}
	}
	slices.SortFunc(zero, func(a, b infinitePublicProfile) int {
		if n := cmp.Compare(a.used, b.used); n != 0 {
			return n
		}
		return strings.Compare(a.hash, b.hash)
	})
	remove := max(0, len(zero)-infiniteZeroProfiles)
	for i, p := range zero {
		if p.used < now.Add(-30*24*time.Hour).Unix() {
			remove = max(remove, i+1)
		}
	}
	if remove == 0 {
		return nil
	}
	if s.publicDB != nil {
		tx, err := s.publicDB.Begin()
		if err != nil {
			return err
		}
		defer tx.Rollback()
		for _, p := range zero[:remove] {
			if _, err = tx.Exec("DELETE FROM infinity_profiles WHERE token_hash=?", p.hash); err != nil {
				return err
			}
			if _, err = tx.Exec("DELETE FROM infinity_scores WHERE id=? OR id=?", p.primary, p.local); err != nil {
				return err
			}
		}
		if err = tx.Commit(); err != nil {
			return err
		}
	}
	s.public.mu.Lock()
	defer s.public.mu.Unlock()
	for _, p := range zero[:remove] {
		delete(s.publicProfiles, p.hash)
		delete(s.publicZeroProfiles, p.hash)
		delete(s.publicScoreOwners, p.primary)
		delete(s.publicScoreOwners, p.local)
		delete(s.public.publicEntries, p.primary)
		delete(s.public.publicEntries, p.local)
	}
	s.public.publicArchiveDirty = true
	return nil
}

func (s *infiniteServer) ResetPublicLeaderboard() (int, error) { return s.resetPublicLeaderboard(nil) }
func (s *infiniteServer) RemovePublicLeaderboard(pattern string) (int, error) {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return 0, err
	}
	return s.resetPublicLeaderboard(re)
}

func (s *infiniteServer) resetPublicLeaderboard(pattern *regexp.Regexp) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return 0, errors.New("server is shutting down")
	}
	if err := s.persistPublicLocked(nil, nil); err != nil {
		return 0, err
	}
	a := s.public
	a.mu.Lock()
	active := make(map[int]bool, len(a.pilots))
	for _, p := range a.pilots {
		active[p.ID] = true
	}
	retained := make(map[int]bool, len(active))
	for id := range active {
		retained[id] = true
	}
	var deleteProfiles []string
	if pattern == nil {
		for hash, p := range s.publicProfiles {
			if active[p.primary] || active[p.local] {
				retained[p.primary] = true
				if p.local != 0 {
					retained[p.local] = true
				}
			} else {
				deleteProfiles = append(deleteProfiles, hash)
			}
		}
	}
	changes := make(map[int]infinitePublicEntry)
	var deleted []int
	affected := 0
	for id, e := range a.publicEntries {
		if pattern != nil && !pattern.MatchString(e.Name) {
			continue
		}
		affected++
		if pattern == nil && !retained[id] {
			deleted = append(deleted, id)
			continue
		}
		e.Score = 0
		e.listed = active[id]
		changes[id] = e
	}
	a.mu.Unlock()
	if s.publicDB != nil {
		tx, err := s.publicDB.Begin()
		if err != nil {
			return 0, err
		}
		defer tx.Rollback()
		for _, hash := range deleteProfiles {
			if _, err = tx.Exec("DELETE FROM infinity_profiles WHERE token_hash=?", hash); err != nil {
				return 0, err
			}
		}
		for _, id := range deleted {
			if _, err = tx.Exec("DELETE FROM infinity_scores WHERE id=?", id); err != nil {
				return 0, err
			}
		}
		for _, e := range changes {
			if _, err = tx.Exec("UPDATE infinity_scores SET score=0,listed=? WHERE id=?", e.listed, e.ID); err != nil {
				return 0, err
			}
		}
		if err = tx.Commit(); err != nil {
			return 0, err
		}
	}
	a.mu.Lock()
	for _, hash := range deleteProfiles {
		p := s.publicProfiles[hash]
		delete(s.publicProfiles, hash)
		delete(s.publicZeroProfiles, hash)
		delete(s.publicScoreOwners, p.primary)
		delete(s.publicScoreOwners, p.local)
	}
	for _, id := range deleted {
		delete(a.publicEntries, id)
		delete(a.publicPending, id)
	}
	for id, e := range changes {
		a.publicEntries[id] = e
		delete(a.publicPending, id)
	}
	for _, list := range [][]*infinitePilot{a.pilots, a.inactiveBots} {
		for _, p := range list {
			if _, ok := changes[p.ID]; ok {
				p.Score = 0
			}
		}
	}
	if pattern == nil {
		a.inactiveBots = nil
	}
	a.publicArchiveDirty = true
	for c, conn := range s.connections {
		if conn.arena == a {
			c.enqueue(map[string]any{"type": "leaderboard_reset", "selected": pattern != nil})
		}
	}
	a.broadcast()
	a.mu.Unlock()
	for id := range changes {
		if hash := s.publicScoreOwners[id]; hash != "" {
			s.refreshPublicZero(hash)
		}
	}
	return affected, nil
}

// Administrative snapshots deliberately contain no bearer or credential hash.
func (s *infiniteServer) AdminLeaderboard() []leaderboardAdminEntry {
	s.mu.Lock()
	defer s.mu.Unlock()
	a := s.public
	a.mu.Lock()
	defer a.mu.Unlock()
	connected := make(map[int]bool, len(a.pilots))
	for _, p := range a.pilots {
		connected[p.ID] = p.Bot || !p.disconnected && (p.client != nil || p.publicKey != "")
	}
	rows := make([]leaderboardAdminEntry, 0, len(a.publicEntries))
	for id, e := range a.publicEntries {
		if e.listed {
			rows = append(rows, leaderboardAdminEntry{ID: id, Name: e.Name, Score: e.Score, Bot: e.Bot, Connected: connected[id]})
		}
	}
	slices.SortFunc(rows, func(a, b leaderboardAdminEntry) int {
		if n := cmp.Compare(b.Score, a.Score); n != 0 {
			return n
		}
		return cmp.Compare(a.ID, b.ID)
	})
	return rows
}
