package main

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"slices"
	"time"
)

var errAccountNameInvalid = errors.New("Use a valid callsign when creating an account.")

var errAccountServerClosed = errors.New("account server is shutting down")

type onlineAccountProfile struct {
	Name       string `json:"name"`
	Score      int    `json:"score"`
	LocalName  string `json:"localName,omitempty"`
	LocalScore *int   `json:"localScore,omitempty"`
}

type onlineAccountInfo struct {
	Names         []string              `json:"names"`
	TotalNames    int                   `json:"totalNames"`
	PublicProfile *onlineAccountProfile `json:"publicProfile,omitempty"`
}

// Copy only this owner's names. Authentication never uses a callsign, and
// the caller cannot enumerate another account by its public names or actor IDs.
func (r *onlineCallsignRegistry) ownerNames(token string) (string, []string, error) {
	hash, valid := publicTokenHash(token)
	if !valid {
		return "", nil, errOnlineOwnerInvalid
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.revoked[hash] {
		return "", nil, errOnlineOwnerRevoked
	}
	if !r.activeOwnerLocked(hash) {
		return "", nil, errOnlineOwnerInvalid
	}
	names := make([]string, 0, len(r.names[hash]))
	for _, name := range r.names[hash] {
		names = append(names, name)
	}
	return hash, names, nil
}

func (s *infiniteServer) accountInfo(token string) (onlineAccountInfo, error) {
	s.mu.Lock()
	info, err := s.accountInfoLocked(token)
	s.mu.Unlock()
	return info, err
}

// The server mutex serializes profile capture with authoritative score commits.
func (s *infiniteServer) accountInfoLocked(token string) (onlineAccountInfo, error) {
	if s.closed {
		return onlineAccountInfo{}, errAccountServerClosed
	}
	if err := s.expireAccounts(); err != nil {
		return onlineAccountInfo{}, err
	}
	hash, names, err := s.hub.callsigns.ownerNames(token)
	if err != nil {
		return onlineAccountInfo{}, err
	}
	info := onlineAccountInfo{Names: names, TotalNames: len(names)}
	if profile, exists := s.publicProfiles[hash]; exists {
		s.public.mu.Lock()
		if primary, exists := s.public.publicEntries[profile.primary]; exists {
			info.PublicProfile = &onlineAccountProfile{Name: primary.Name, Score: primary.Score}
		}
		s.public.mu.Unlock()
	}
	if len(names) == 1 {
		if info.PublicProfile != nil {
			info.PublicProfile.Name = names[0]
		}
	} else if info.PublicProfile != nil {
		info.Names = []string{info.PublicProfile.Name}
	} else if len(names) > 1 {
		slices.Sort(names)
		info.Names = names[:1]
	}
	info.TotalNames = len(info.Names)
	return info, nil
}

// Account-key import validates ownership without joining, allocating a pilot,
// replacing another device, renewing a claim, or accepting any score fields.
func (a *App) onlineAccount(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		accountError(w, http.StatusMethodNotAllowed, "method_not_allowed", "Use POST to check an account key.")
		return
	}
	if !validOrigin(r, a.origins) {
		accountError(w, http.StatusForbidden, "origin_not_allowed", "Origin not allowed.")
		return
	}
	ip := connectionSource(r.RemoteAddr)
	if !a.reserve(ip, time.Now()) {
		w.Header().Set("Retry-After", "60")
		accountError(w, http.StatusTooManyRequests, "rate_limited", "Too many account checks. Try again shortly.")
		return
	}
	defer a.release(ip)
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" {
		accountError(w, http.StatusUnsupportedMediaType, "bad_content_type", "Use application/json.")
		return
	}
	var request struct {
		PublicToken    string `json:"publicToken"`
		NewPublicToken string `json:"newPublicToken"`
		Name           string `json:"name"`
		SignIn         bool   `json:"signIn"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&request) != nil || decoder.Decode(new(any)) != io.EOF || len(request.PublicToken) > 128 || len(request.NewPublicToken) > 128 || len(request.Name) > 256 || r.URL.Path != "/api/account/create" && request.Name != "" || (r.URL.Path == "/api/account/rotate" || r.URL.Path == "/api/account/release") && request.SignIn || r.URL.Path != "/api/account/rotate" && request.NewPublicToken != "" {
		accountError(w, http.StatusBadRequest, "bad_request", "Invalid account-key request.")
		return
	}
	var info any
	if r.URL.Path == "/api/account/rotate" {
		info, err = a.infinite.rotateAccount(request.PublicToken, request.NewPublicToken)
	} else if r.URL.Path == "/api/account/release" {
		err = a.infinite.releaseAccount(request.PublicToken)
		info = map[string]bool{"released": true}
	} else if r.URL.Path == "/api/account/create" {
		info, err = a.infinite.createAccount(request.PublicToken, request.Name)
	} else {
		if request.Name != "" {
			accountError(w, 400, "bad_request", "Name is only accepted when creating an account.")
			return
		}
		if request.SignIn {
			info, err = a.infinite.signInAccount(request.PublicToken)
		} else {
			info, err = a.infinite.accountInfo(request.PublicToken)
		}
	}
	var conflict *callsignConflictError
	var reserved *callsignReservedError
	if errors.Is(err, errAccountNameInvalid) {
		accountError(w, 400, "bad_request", err.Error())
		return
	}
	if errors.Is(err, errCallsignImmutable) {
		accountError(w, 409, "callsign_immutable", err.Error())
		return
	}
	if errors.As(err, &conflict) {
		accountError(w, 409, "callsign_taken", err.Error())
		return
	}
	if errors.As(err, &reserved) {
		accountError(w, 409, "callsign_reserved", err.Error())
		return
	}
	if errors.Is(err, errOnlineOwnerRevoked) {
		accountError(w, http.StatusUnauthorized, "account_key_revoked", infiniteAccountKeyRevoked)
		return
	}
	if errors.Is(err, errNewAccountKeyInvalid) {
		accountError(w, http.StatusBadRequest, "new_key_invalid", "Generate a new unused account key before resetting it.")
		return
	}
	if errors.Is(err, errOnlineOwnerInvalid) {
		accountError(w, http.StatusUnauthorized, "account_key_invalid", "That account key is invalid or unavailable.")
		return
	}
	if err != nil {
		accountError(w, http.StatusServiceUnavailable, "server_busy", "The account server is unavailable. Try again shortly.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(info)
}

func accountError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"code": code, "message": message})
}

func (s *infiniteServer) createAccount(token, name string) (onlineAccountInfo, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return onlineAccountInfo{}, errAccountServerClosed
	}
	if err := s.expireAccounts(); err != nil {
		return onlineAccountInfo{}, err
	}
	if _, valid := publicTokenHash(token); !valid {
		return onlineAccountInfo{}, errNewAccountKeyInvalid
	}
	if name == "" || name != cleanCallsign(name) {
		return onlineAccountInfo{}, errAccountNameInvalid
	}
	if _, err := s.hub.callsigns.claimSeatAccounts([]accountSeatClaim{{token: token, name: name, newAccount: true}}, nil); err != nil {
		return onlineAccountInfo{}, err
	}
	return s.accountInfoLocked(token)
}
func (s *infiniteServer) signInAccount(token string) (onlineAccountInfo, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.expireAccounts(); err != nil {
		return onlineAccountInfo{}, err
	}
	r := s.hub.callsigns
	hash, valid := publicTokenHash(token)
	if !valid {
		return onlineAccountInfo{}, errOnlineOwnerInvalid
	}
	r.mu.Lock()
	err := r.touchAccountLocked(hash)
	r.mu.Unlock()
	if err != nil {
		return onlineAccountInfo{}, err
	}
	return s.accountInfoLocked(token)
}
