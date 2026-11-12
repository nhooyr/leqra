package main

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"slices"
	"strings"
	"time"
)

const accountAliasPreviewLimit = 128

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

// Copy only this owner's aliases. Authentication never uses a callsign, and
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
	if !r.owners[hash] {
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
	return accountPreview(info), err
}

// The server mutex serializes profile capture with authoritative score commits.
func (s *infiniteServer) accountInfoLocked(token string) (onlineAccountInfo, error) {
	if s.closed {
		return onlineAccountInfo{}, errAccountServerClosed
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
			if profile.localEnabled {
				if local, exists := s.public.publicEntries[profile.local]; exists {
					info.PublicProfile.LocalName = local.Name
					score := local.Score
					info.PublicProfile.LocalScore = &score
				}
			}
		}
		s.public.mu.Unlock()
	}
	return info, nil
}

func accountPreview(info onlineAccountInfo) onlineAccountInfo {
	// Sorting and preview truncation happen after simulation locks are released.
	slices.SortFunc(info.Names, func(a, b string) int {
		if n := strings.Compare(canonicalCallsign(a), canonicalCallsign(b)); n != 0 {
			return n
		}
		return strings.Compare(a, b)
	})
	if len(info.Names) > accountAliasPreviewLimit {
		info.Names = info.Names[:accountAliasPreviewLimit]
	}
	return info
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
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&request) != nil || decoder.Decode(new(any)) != io.EOF || len(request.PublicToken) > 128 || len(request.NewPublicToken) > 128 || r.URL.Path != "/api/account/rotate" && request.NewPublicToken != "" {
		accountError(w, http.StatusBadRequest, "bad_request", "Invalid account-key request.")
		return
	}
	var info any
	if r.URL.Path == "/api/account/rotate" {
		info, err = a.infinite.rotateAccount(request.PublicToken, request.NewPublicToken)
	} else {
		info, err = a.infinite.accountInfo(request.PublicToken)
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
