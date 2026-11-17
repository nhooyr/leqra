package main

import (
	"database/sql"
	"errors"
	"strings"
	"unicode"
)

// Callsign ownership must not change when the Go toolchain upgrades its Unicode
// tables. Later Unicode versions added these equivalences to the Go 1.23 rules;
// preserve the existing distinctions so two prior owners are never merged.
func canonicalCallsignRune(r rune) rune {
	switch r {
	case 0x1FD3, 0x1FE3, 0xFB06:
		return r
	}
	smallest := r
	for next := unicode.SimpleFold(r); next != r; next = unicode.SimpleFold(next) {
		smallest = min(smallest, next)
	}
	return unicode.ToLower(smallest)
}
func canonicalCallsign(name string) string {
	var key strings.Builder
	for _, r := range cleanCallsign(name) {
		key.WriteRune(canonicalCallsignRune(r))
	}
	return key.String()
}

// A newer-toolchain server may already have persisted a merged spelling.
// Recognize only that exact former key, never an arbitrary corrupt claim.
func legacyUnicode17Callsign(name string) string {
	var key strings.Builder
	for _, r := range cleanCallsign(name) {
		switch r {
		case 0x1FD3:
			r = 0x0390
		case 0x1FE3:
			r = 0x03B0
		case 0xFB06:
			r = 0xFB05
		default:
			r = canonicalCallsignRune(r)
		}
		key.WriteRune(r)
	}
	return key.String()
}

type callsignFoldMigration struct{ old, current, display, owner string }

func migrateCallsignFolds(db *sql.DB, changes []callsignFoldMigration) error {
	if len(changes) == 0 {
		return nil
	}
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, change := range changes {
		result, err := tx.Exec("UPDATE online_callsigns SET canonical_name=? WHERE canonical_name=? AND display_name=? AND owner_hash=?", change.current, change.old, change.display, change.owner)
		if err != nil {
			return err
		}
		count, err := result.RowsAffected()
		if err != nil {
			return err
		}
		if count != 1 {
			return errors.New("callsign changed during canonical migration")
		}
		if _, err = tx.Exec("UPDATE online_seat_migrations SET name=? WHERE new_hash=? AND name=?", change.current, change.owner, change.old); err != nil {
			return err
		}
	}
	return tx.Commit()
}
