package main

import (
	"errors"
	"math/rand/v2"
)

func (s *infiniteServer) RandomizePublicColors() (int, error) {
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
	var leader infinitePublicEntry
	for _, entry := range a.publicEntries {
		if entry.listed && (leader.ID == 0 || compareInfiniteLeaders(entry.infiniteLeader, leader.infiniteLeader) < 0) {
			leader = entry
		}
	}
	colors := make(map[int]int, len(a.publicEntries))
	for id, entry := range a.publicEntries {
		color := 0
		if id != leader.ID {
			choices := len(tankColors) - 1
			if entry.ColorIndex > 0 {
				choices--
			}
			color = 1 + rand.IntN(choices)
			if entry.ColorIndex > 0 && color >= entry.ColorIndex {
				color++
			}
		}
		colors[id] = color
	}
	a.mu.Unlock()

	// Commit every paint change together before any live snapshot can expose it.
	if s.publicDB != nil {
		tx, err := s.publicDB.Begin()
		if err != nil {
			return 0, err
		}
		defer tx.Rollback()
		for id, color := range colors {
			if _, err := tx.Exec("UPDATE infinity_scores SET color_index=? WHERE id=?", color, id); err != nil {
				return 0, err
			}
		}
		if err := tx.Commit(); err != nil {
			return 0, err
		}
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	for id, color := range colors {
		entry := a.publicEntries[id]
		entry.ColorIndex = color
		a.publicEntries[id] = entry
		delete(a.publicPending, id)
	}
	setColor := func(pilot *infinitePilot) {
		if pilot != nil {
			if color, ok := colors[pilot.ID]; ok {
				pilot.ColorIndex = color
			}
		}
	}
	for _, list := range [][]*infinitePilot{a.pilots, a.inactiveBots} {
		for _, pilot := range list {
			setColor(pilot)
		}
	}
	for _, reservation := range s.reservations {
		if reservation.connection.arena == a {
			setColor(reservation.connection.pilot)
			setColor(reservation.connection.local)
		}
	}
	a.publicArchiveDirty = true
	a.broadcast()
	return len(colors), nil
}
