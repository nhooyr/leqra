package main

import (
	"slices"
	"strings"
)

type leaderboardAdminAccount struct {
	ID    string   `json:"id"`
	Names []string `json:"names"`
	hash  string
}

// Include registered accounts without public scores. Raw keys and owner hashes
// never appear in the dashboard's account list.
func (s *infiniteServer) AdminAccounts() []leaderboardAdminAccount {
	r := s.hub.callsigns
	r.mu.Lock()
	defer r.mu.Unlock()
	accounts := make([]leaderboardAdminAccount, 0, len(r.names))
	for hash, claimed := range r.names {
		if !r.activeOwnerLocked(hash) || len(claimed) == 0 {
			continue
		}
		names := make([]string, 0, len(claimed))
		for _, name := range claimed {
			names = append(names, name)
		}
		slices.Sort(names)
		accounts = append(accounts, leaderboardAdminAccount{Names: names, hash: hash})
	}
	slices.SortFunc(accounts, func(a, b leaderboardAdminAccount) int {
		return strings.Compare(a.Names[0], b.Names[0])
	})
	return accounts
}

func (s *infiniteServer) RecoverAdminAccount(hash, newToken string) error {
	_, err := s.rotateAccountHash(hash, newToken)
	return err
}
