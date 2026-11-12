package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"strings"
	"sync"
	"unicode"
	"unicode/utf8"
)

var errOnlineOwnerInvalid = errors.New(infinitePublicResumeInvalid)
var errOnlineOwnerRevoked = errors.New(infiniteAccountKeyRevoked)

const infiniteAccountKeyRevoked = "This account key was reset. Import the new key to sign in again."

type callsignConflict struct {
	Seat int    `json:"seat"`
	Name string `json:"name"`
}
type callsignAvailability struct {
	Seat      int    `json:"seat"`
	Name      string `json:"name"`
	Available bool   `json:"available"`
}
type callsignConflictError struct{ Conflicts []callsignConflict }

func (e *callsignConflictError) Error() string {
	names := make([]string, 0, len(e.Conflicts))
	for _, c := range e.Conflicts {
		names = append(names, fmt.Sprintf("%s (P%d)", c.Name, c.Seat+1))
	}
	return "Choose an unused online callsign for " + strings.Join(names, ", ") + ". If this is your callsign, import its account key from the other device."
}

type onlineCallsignRegistry struct {
	mu             sync.Mutex
	db             *sql.DB
	owners         map[string]bool
	claims         map[string]string
	names          map[string]map[string]string // Owner hash -> canonical name -> first display spelling.
	revoked        map[string]bool
	seatMigrations map[string]seatAccountMigration
}

func newOnlineCallsignRegistry() *onlineCallsignRegistry {
	return &onlineCallsignRegistry{owners: make(map[string]bool), claims: make(map[string]string), names: make(map[string]map[string]string), revoked: make(map[string]bool), seatMigrations: make(map[string]seatAccountMigration)}
}
func canonicalCallsign(name string) string {
	var key strings.Builder
	for _, r := range cleanCallsign(name) {
		smallest := r
		for folded := unicode.SimpleFold(r); folded != r; folded = unicode.SimpleFold(folded) {
			smallest = min(smallest, folded)
		}
		key.WriteRune(unicode.ToLower(smallest))
	}
	return key.String()
}

// Call only at startup, before serving Hub or Infinity connections. Registry
// rows have no foreign key to score profiles: resets never release a callsign.
func (r *onlineCallsignRegistry) open(db *sql.DB) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, query := range []string{
		`CREATE TABLE IF NOT EXISTS online_owners (token_hash TEXT PRIMARY KEY) WITHOUT ROWID`,
		`CREATE TABLE IF NOT EXISTS online_callsigns (canonical_name TEXT PRIMARY KEY, display_name TEXT NOT NULL, owner_hash TEXT NOT NULL REFERENCES online_owners(token_hash)) WITHOUT ROWID`,
		`CREATE INDEX IF NOT EXISTS online_callsigns_owner ON online_callsigns(owner_hash)`,
		`CREATE TABLE IF NOT EXISTS online_revoked (token_hash TEXT PRIMARY KEY) WITHOUT ROWID`,
		`CREATE TABLE IF NOT EXISTS online_seat_migrations (new_hash TEXT PRIMARY KEY, previous_hash TEXT NOT NULL, name TEXT NOT NULL) WITHOUT ROWID`,
		`CREATE UNIQUE INDEX IF NOT EXISTS online_seat_migrations_previous ON online_seat_migrations(previous_hash)`,
	} {
		if _, err := db.Exec(query); err != nil {
			return err
		}
	}
	owners := make(map[string]bool)
	rows, err := db.Query("SELECT token_hash FROM online_owners")
	if err != nil {
		return err
	}
	for rows.Next() {
		var hash string
		if err = rows.Scan(&hash); err != nil {
			break
		}
		digest, decodeErr := hex.DecodeString(hash)
		if decodeErr != nil || len(digest) != sha256.Size {
			err = errors.New("invalid online owner")
			break
		}
		owners[hash] = true
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return err
	}
	claims := make(map[string]string)
	names := make(map[string]map[string]string)
	rows, err = db.Query("SELECT canonical_name,display_name,owner_hash FROM online_callsigns")
	if err != nil {
		return err
	}
	for rows.Next() {
		var name, display, hash string
		if err = rows.Scan(&name, &display, &hash); err != nil {
			break
		}
		if name == "" || name != canonicalCallsign(display) || !owners[hash] {
			err = errors.New("invalid online callsign claim")
			break
		}
		claims[name] = hash
		if names[hash] == nil {
			names[hash] = make(map[string]string)
		}
		names[hash][name] = display
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return err
	}
	revoked := make(map[string]bool)
	rows, err = db.Query("SELECT token_hash FROM online_revoked")
	if err != nil {
		return err
	}
	for rows.Next() {
		var hash string
		if err = rows.Scan(&hash); err != nil {
			break
		}
		digest, decodeErr := hex.DecodeString(hash)
		if decodeErr != nil || len(digest) != sha256.Size || owners[hash] {
			err = errors.New("invalid revoked online owner")
			break
		}
		revoked[hash] = true
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return err
	}
	r.db = db
	r.owners = owners
	r.claims = claims
	r.names = names
	r.revoked = revoked
	r.seatMigrations = make(map[string]seatAccountMigration)
	rows, err = db.Query("SELECT new_hash,previous_hash,name FROM online_seat_migrations")
	if err != nil {
		return err
	}
	for rows.Next() {
		var m seatAccountMigration
		if err = rows.Scan(&m.next, &m.previous, &m.name); err != nil {
			break
		}
		if !owners[m.next] || !owners[m.previous] || m.next == m.previous || canonicalCallsign(m.name) != m.name {
			err = errors.New("invalid independent seat migration")
			break
		}
		r.seatMigrations[m.next] = m
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return err
	}
	return nil
}
func (r *onlineCallsignRegistry) owner(token string) (string, bool) {
	hash, valid := publicTokenHash(token)
	if !valid {
		return "", false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return hash, r.owners[hash]
}
func (r *onlineCallsignRegistry) revokedOwner(token string) bool {
	hash, valid := publicTokenHash(token)
	if !valid {
		return false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.revoked[hash]
}
func (r *onlineCallsignRegistry) availability(token string, names []string) []callsignAvailability {
	hash, valid := publicTokenHash(token)
	r.mu.Lock()
	defer r.mu.Unlock()
	valid = valid && r.owners[hash]
	rows := make([]callsignAvailability, len(names))
	seen := make(map[string]bool, len(names))
	for i, name := range names {
		clean := cleanCallsign(name)
		key := canonicalCallsign(clean)
		owner, claimed := r.claims[key]
		available := key != "" && !seen[key] && (!claimed || valid && owner == hash)
		rows[i] = callsignAvailability{i, clean, available}
		seen[key] = true
	}
	return rows
}
func (r *onlineCallsignRegistry) claim(token string, names []string) (string, error) {
	return r.claimWithCommit(token, names, nil)
}

// A batch either claims all names or none. The optional transaction callback
// lets public joins save their score identity in this same durable transaction.
// It must not call Hub, Infinity, or registry methods while registry.mu is held.
func (r *onlineCallsignRegistry) claimWithCommit(token string, names []string, commit func(*sql.Tx, string) error) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var hash string
	if token == "" {
		var err error
		token, hash, err = newPublicToken()
		if err != nil {
			return "", err
		}
	} else {
		var valid bool
		hash, valid = publicTokenHash(token)
		if valid && r.revoked[hash] {
			return "", errOnlineOwnerRevoked
		}
		if !valid || !r.owners[hash] {
			return "", errOnlineOwnerInvalid
		}
	}
	seen := make(map[string]bool, len(names))
	var conflicts []callsignConflict
	for i, name := range names {
		key := canonicalCallsign(name)
		owner, claimed := r.claims[key]
		if key == "" || seen[key] || claimed && owner != hash {
			conflicts = append(conflicts, callsignConflict{i, cleanCallsign(name)})
		}
		seen[key] = true
	}
	if len(conflicts) > 0 {
		return "", &callsignConflictError{Conflicts: conflicts}
	}
	var tx *sql.Tx
	if r.db != nil {
		var err error
		tx, err = r.db.Begin()
		if err != nil {
			return "", err
		}
		defer tx.Rollback()
		if _, err = tx.Exec("INSERT OR IGNORE INTO online_owners(token_hash) VALUES(?)", hash); err != nil {
			return "", err
		}
		for _, name := range names {
			if _, err = tx.Exec("INSERT OR IGNORE INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?)", canonicalCallsign(name), cleanCallsign(name), hash); err != nil {
				return "", err
			}
		}
	}
	if commit != nil {
		if err := commit(tx, hash); err != nil {
			return "", err
		}
	}
	if tx != nil {
		if err := tx.Commit(); err != nil {
			return "", err
		}
	}
	r.owners[hash] = true
	if r.names[hash] == nil {
		r.names[hash] = make(map[string]string)
	}
	for _, name := range names {
		key := canonicalCallsign(name)
		if _, claimed := r.claims[key]; !claimed {
			r.names[hash][key] = cleanCallsign(name)
		}
		r.claims[key] = hash
	}
	return token, nil
}

// Availability is advisory and read-only. The join/rename transaction still
// performs the authoritative atomic check; no bearer or score is returned.
func (a *App) callsignAvailability(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if !validOrigin(r, a.origins) {
		http.Error(w, "Origin not allowed", http.StatusForbidden)
		return
	}
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" {
		http.Error(w, "Use application/json", http.StatusUnsupportedMediaType)
		return
	}
	var request struct {
		PublicToken         string   `json:"publicToken"`
		Names               []string `json:"names"`
		LocalPublicToken    string   `json:"localPublicToken"`
		IndependentAccounts bool     `json:"independentAccounts"`
		LocalNewAccount     bool     `json:"localNewAccount"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&request) != nil || decoder.Decode(new(any)) != io.EOF || len(request.Names) < 1 || len(request.Names) > 8 || len(request.PublicToken) > 128 || len(request.LocalPublicToken) > 128 {
		http.Error(w, "Invalid callsigns", http.StatusBadRequest)
		return
	}
	for _, name := range request.Names {
		if !utf8.ValidString(name) || len(name) > 256 {
			http.Error(w, "Invalid callsign", http.StatusBadRequest)
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	rows := a.hub.callsigns.availability(request.PublicToken, request.Names)
	if request.IndependentAccounts && len(rows) > 1 {
		second := a.hub.callsigns.availability(request.LocalPublicToken, request.Names[1:])
		for i := range second {
			rows[i+1].Available = second[i].Available
		}
		if request.LocalNewAccount && request.LocalPublicToken != "" {
			r := a.hub.callsigns
			hash, valid := r.owner(request.PublicToken)
			localHash, localValid := publicTokenHash(request.LocalPublicToken)
			r.mu.Lock()
			if valid && localValid && !r.owners[localHash] && !r.revoked[localHash] && r.claims[canonicalCallsign(rows[1].Name)] == hash {
				rows[1].Available = true
			}
			r.mu.Unlock()
		}
		if canonicalCallsign(rows[0].Name) == canonicalCallsign(rows[1].Name) || request.PublicToken != "" && request.PublicToken == request.LocalPublicToken {
			rows[1].Available = false
		}
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"names": rows})
}
