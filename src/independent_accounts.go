package main

import (
	"database/sql"
	"errors"
)

type seatAccountError struct {
	seat int
	err  error
}

func (e *seatAccountError) Error() string { return e.err.Error() }
func (e *seatAccountError) Unwrap() error { return e.err }

type accountSeatClaim struct {
	token, name, transferFrom string
	newAccount                bool
}

type claimedSeatAccount struct {
	token, hash, name string
	fresh             bool
	migration         *seatAccountMigration
	consumed          bool
}

type seatAccountMigration struct{ next, previous, name string }

var errSameSeatAccount = errors.New("P1 and P2 need separate account keys.")
var errSeatMigrationPending = errors.New("an independent P2 account migration is already pending")

// Every seat is validated before a transaction allocates any owner, claims any
// name, or migrates a legacy shared score. New P2 keys were saved by the client
// before the join so losing its welcome cannot orphan migrated progress.
func (r *onlineCallsignRegistry) claimSeatAccounts(requests []accountSeatClaim, commit func(*sql.Tx, []claimedSeatAccount) error) ([]claimedSeatAccount, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := r.expireAccountsLocked(); err != nil {
		return nil, err
	}
	accounts := make([]claimedSeatAccount, len(requests))
	seenNames, seenOwners := make(map[string]bool), make(map[string]bool)
	var conflicts []callsignConflict
	var reserved []callsignConflict
	for seat, request := range requests {
		token := request.token
		if token == "" {
			if seat > 0 {
				return nil, &seatAccountError{seat, errNewAccountKeyInvalid}
			}
			var err error
			token, _, err = newPublicToken()
			if err != nil {
				return nil, &seatAccountError{seat, err}
			}
		}
		hash, valid := publicTokenHash(token)
		if !valid {
			return nil, &seatAccountError{seat, errOnlineOwnerInvalid}
		}
		if r.expired[hash] {
			return nil, &seatAccountError{seat, errOnlineOwnerInvalid}
		}
		if r.revoked[hash] {
			return nil, &seatAccountError{seat, errOnlineOwnerRevoked}
		}
		known := r.activeOwnerLocked(hash)
		fresh := !known || request.newAccount && r.generatedFresh[hash]
		if request.token != "" && !known && !request.newAccount {
			return nil, &seatAccountError{seat, errOnlineOwnerInvalid}
		}
		if seenOwners[hash] {
			return nil, &seatAccountError{seat, errSameSeatAccount}
		}
		seenOwners[hash] = true
		name, key := cleanName(request.name), canonicalCallsign(request.name)
		if reservedCallsign(name) {
			reserved = append(reserved, callsignConflict{Seat: seat, Name: name})
		}
		if !reservedCallsign(name) {
			if err := r.immutableNamesLocked(hash, []string{request.name}); err != nil {
				return nil, &seatAccountError{seat, err}
			}
		}
		owner, claimed := r.callsignOwnerLocked(key)
		transferHash, transferValid := publicTokenHash(request.transferFrom)
		authorizedSplit := fresh && transferValid && r.owners[transferHash] && !r.revoked[transferHash]
		if authorizedSplit {
			// Mirror SQLite's unique previous-owner index before any allocation.
			// Until its first split is applied, a second candidate must not take
			// ownership of the same legacy score in an in-memory registry either.
			for _, pending := range r.seatMigrations {
				if pending.previous == transferHash {
					return nil, &seatAccountError{seat, errSeatMigrationPending}
				}
			}
		}
		transfer := authorizedSplit && owner == transferHash
		if key == "" || seenNames[key] || claimed && owner != hash && !transfer {
			conflicts = append(conflicts, callsignConflict{seat, cleanCallsign(request.name)})
		}
		seenNames[key] = true
		accounts[seat] = claimedSeatAccount{token: token, hash: hash, name: name, fresh: fresh}
		if authorizedSplit {
			accounts[seat].migration = &seatAccountMigration{next: hash, previous: transferHash, name: key}
		}
	}
	if len(reserved) != 0 {
		return nil, &callsignReservedError{Conflicts: reserved}
	}
	if len(conflicts) != 0 {
		return nil, &callsignConflictError{Conflicts: conflicts}
	}
	var tx *sql.Tx
	if r.db != nil {
		var err error
		tx, err = r.db.Begin()
		if err != nil {
			return nil, err
		}
		defer tx.Rollback()
		for _, account := range accounts {
			if _, err = tx.Exec("INSERT OR IGNORE INTO online_owners(token_hash) VALUES(?)", account.hash); err != nil {
				return nil, err
			}
			if err = r.writeAccountUseLocked(tx, account.hash); err != nil {
				return nil, err
			}
			if r.generatedFresh[account.hash] {
				if _, err = tx.Exec("DELETE FROM online_generated_fresh WHERE token_hash=?", account.hash); err != nil {
					return nil, err
				}
			}
		}
		// Replace each current name in the same transaction as any legacy split.
		for _, account := range accounts {
			if _, err = tx.Exec("DELETE FROM online_callsigns WHERE owner_hash=? AND canonical_name<>?", account.hash, canonicalCallsign(account.name)); err != nil {
				return nil, err
			}
		}
		for _, account := range accounts {
			key := canonicalCallsign(account.name)
			if owner, claimed := r.claims[key]; claimed && owner != account.hash {
				if _, err = tx.Exec("INSERT INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?) ON CONFLICT(canonical_name) DO UPDATE SET owner_hash=excluded.owner_hash,display_name=excluded.display_name", key, account.name, account.hash); err != nil {
					return nil, err
				}
			} else if _, err = tx.Exec("INSERT OR IGNORE INTO online_callsigns(canonical_name,display_name,owner_hash) VALUES(?,?,?)", key, account.name, account.hash); err != nil {
				return nil, err
			}
		}
	}
	if tx != nil {
		for _, account := range accounts {
			if m := account.migration; m != nil {
				if _, err := tx.Exec("INSERT INTO online_seat_migrations(new_hash,previous_hash,name) VALUES(?,?,?)", m.next, m.previous, m.name); err != nil {
					return nil, err
				}
			}
		}
	}
	if commit != nil {
		if err := commit(tx, accounts); err != nil {
			return nil, err
		}
	}
	if tx != nil {
		if err := tx.Commit(); err != nil {
			return nil, err
		}
	}
	for _, account := range accounts {
		r.owners[account.hash] = true
		r.lastUsed[account.hash] = r.now().Unix()
		delete(r.generatedFresh, account.hash)
		key := canonicalCallsign(account.name)
		display := account.name
		if owner, claimed := r.claims[key]; claimed {
			display = r.names[owner][key]
			if owner != account.hash {
				delete(r.names[owner], key)
			}
		}
		if display == "" {
			display = account.name
		}
		r.replaceNamesLocked(account.hash, []string{display})
		if account.migration != nil && !account.consumed {
			r.seatMigrations[account.hash] = *account.migration
		}
	}
	return accounts, nil
}

func accountErrorSeat(err error) int {
	var seat *seatAccountError
	if errors.As(err, &seat) {
		return seat.seat
	}
	return 0
}
