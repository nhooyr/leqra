package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base32"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
)

type callsignGenerationAccount struct {
	Seat        int
	PublicToken string
}

type generatedCallsign struct {
	Seat int    `json:"seat"`
	Name string `json:"name"`
}

var errCallsignGenerationRequest = errors.New("invalid callsign generation request")
var errCallsignGenerationBusy = errors.New("could not generate an unused callsign")

func callsignGenerationID(value string) (string, bool) {
	if len(value) != 36 {
		return "", false
	}
	for i, c := range value {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return "", false
			}
			continue
		}
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F') {
			return "", false
		}
	}
	return strings.ToLower(value), true
}

func generatedCallsignCandidate(token, requestID string, attempt int) string {
	mac := hmac.New(sha256.New, []byte(token))
	mac.Write([]byte("leqra-generated-v1|" + requestID + "|" + strconv.Itoa(attempt)))
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	suffix := mac.Sum(nil)[:6]
	for i := range suffix {
		suffix[i] = alphabet[suffix[i]&31]
	}
	return "pilot#" + string(suffix)
}

// A retry can outlive an upgrade. Retain an alias already claimed by the old
// generator for the same bearer and UUID rather than silently adding an alias.
func legacyGeneratedCallsignCandidate(token, requestID string, attempt int) string {
	mac := hmac.New(sha256.New, []byte(token))
	mac.Write([]byte("leqra-generated-v1|" + requestID + "|" + strconv.Itoa(attempt)))
	suffix := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(mac.Sum(nil))[:10]
	return "pilot-" + strings.ToLower(suffix)
}

// The random, pre-saved bearer and request UUID select one uniform candidate.
// Existing claims make retries stable without persisting raw keys or nonces.
// A new UUID deliberately requests another alias for the same account.
func (r *onlineCallsignRegistry) generateCallsigns(requestID string, accounts []callsignGenerationAccount) ([]generatedCallsign, error) {
	id, valid := callsignGenerationID(requestID)
	if !valid || len(accounts) < 1 || len(accounts) > 2 {
		return nil, errCallsignGenerationRequest
	}
	accounts = slices.Clone(accounts)
	slices.SortFunc(accounts, func(a, b callsignGenerationAccount) int { return a.Seat - b.Seat })
	r.mu.Lock()
	defer r.mu.Unlock()
	hashes := make([]string, len(accounts))
	seenSeats, seenOwners := map[int]bool{}, map[string]bool{}
	for i, account := range accounts {
		hash, valid := publicTokenHash(account.PublicToken)
		if !valid || account.Seat < 0 || account.Seat > 1 || seenSeats[account.Seat] || seenOwners[hash] {
			return nil, errCallsignGenerationRequest
		}
		if r.revoked[hash] {
			return nil, &seatAccountError{account.Seat, errOnlineOwnerRevoked}
		}
		hashes[i] = hash
		seenSeats[account.Seat], seenOwners[hash] = true, true
	}
	names := make([]generatedCallsign, len(accounts))
	selected := make(map[string]string, len(accounts))
	for i, account := range accounts {
		found := false
		for attempt := 0; attempt < 64; attempt++ {
			legacy := legacyGeneratedCallsignCandidate(account.PublicToken, id, attempt)
			if r.claims[canonicalCallsign(legacy)] == hashes[i] {
				names[i] = generatedCallsign{Seat: account.Seat, Name: legacy}
				selected[canonicalCallsign(legacy)] = hashes[i]
				found = true
				break
			}
		}
		if found {
			continue
		}
		for attempt := 0; attempt < 64; attempt++ {
			name := generatedCallsignCandidate(account.PublicToken, id, attempt)
			key := canonicalCallsign(name)
			owner, claimed := r.claims[key]
			if reservedCallsign(name) || claimed && owner != hashes[i] || selected[key] != "" && selected[key] != hashes[i] {
				continue
			}
			names[i] = generatedCallsign{Seat: account.Seat, Name: name}
			selected[key] = hashes[i]
			found = true
			break
		}
		if !found {
			return nil, errCallsignGenerationBusy
		}
	}
	if r.db != nil {
		tx, err := r.db.Begin()
		if err != nil {
			return nil, err
		}
		defer tx.Rollback()
		for i, row := range names {
			if _, err = tx.Exec("INSERT OR IGNORE INTO online_owners(token_hash) VALUES(?)", hashes[i]); err != nil {
				return nil, err
			}
			if _, err = tx.Exec("INSERT OR IGNORE INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?)", canonicalCallsign(row.Name), row.Name, hashes[i]); err != nil {
				return nil, err
			}
			if !r.owners[hashes[i]] {
				if _, err = tx.Exec("INSERT INTO online_generated_fresh(token_hash) VALUES(?)", hashes[i]); err != nil {
					return nil, err
				}
			}
		}
		if err = tx.Commit(); err != nil {
			return nil, err
		}
	}
	for i, row := range names {
		hash, key := hashes[i], canonicalCallsign(row.Name)
		if !r.owners[hash] {
			r.generatedFresh[hash] = true
		}
		r.owners[hash] = true
		if r.names[hash] == nil {
			r.names[hash] = map[string]string{}
		}
		if _, claimed := r.claims[key]; !claimed {
			r.names[hash][key] = row.Name
		}
		r.claims[key] = hash
	}
	return names, nil
}

func (a *App) generateCallsigns(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		accountError(w, 405, "method_not_allowed", "Use POST to generate callsigns.")
		return
	}
	if !validOrigin(r, a.origins) {
		accountError(w, 403, "origin_not_allowed", "Origin not allowed.")
		return
	}
	ip := connectionSource(r.RemoteAddr)
	if !a.reserve(ip, time.Now()) {
		w.Header().Set("Retry-After", "60")
		accountError(w, 429, "rate_limited", "Too many callsign requests. Try again shortly.")
		return
	}
	defer a.release(ip)
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" {
		accountError(w, 415, "bad_content_type", "Use application/json.")
		return
	}
	var request struct {
		RequestID string `json:"requestId"`
		Accounts  []struct {
			Seat        *int    `json:"seat"`
			PublicToken *string `json:"publicToken"`
		} `json:"accounts"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&request) != nil || decoder.Decode(new(any)) != io.EOF || len(request.Accounts) < 1 || len(request.Accounts) > 2 {
		accountError(w, 400, "bad_request", "Invalid callsign generation request.")
		return
	}
	accounts := make([]callsignGenerationAccount, len(request.Accounts))
	for i, account := range request.Accounts {
		if account.Seat == nil || account.PublicToken == nil {
			accountError(w, 400, "bad_request", "Invalid callsign generation request.")
			return
		}
		accounts[i] = callsignGenerationAccount{Seat: *account.Seat, PublicToken: *account.PublicToken}
	}
	a.infinite.mu.Lock()
	var names []generatedCallsign
	if a.infinite.closed {
		err = errAccountServerClosed
	} else {
		names, err = a.hub.callsigns.generateCallsigns(request.RequestID, accounts)
	}
	a.infinite.mu.Unlock()
	if errors.Is(err, errCallsignGenerationRequest) {
		accountError(w, 400, "bad_request", "Invalid callsign generation request.")
		return
	}
	if errors.Is(err, errOnlineOwnerRevoked) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(401)
		json.NewEncoder(w).Encode(map[string]any{"code": "account_key_revoked", "message": infiniteAccountKeyRevoked, "seat": accountErrorSeat(err)})
		return
	}
	if err != nil {
		accountError(w, 503, "server_busy", "Callsign generation is unavailable. Try again shortly.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"names": names})
}
