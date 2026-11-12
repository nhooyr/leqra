package main

import (
	"encoding/json"
	"net/http"
)

type infiniteStatusLeader struct {
	infiniteLeader
	Rank int `json:"rank"`
}

// The ready room can show the public standings without allocating a tank.
func (a *App) infinityStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	arena := a.infinite.public
	arena.mu.Lock()
	players, tankCount := arena.connected, len(arena.pilots)
	ranked := arena.rankedLeaders(nil)
	leaders := make([]infiniteStatusLeader, min(len(ranked), infiniteLeaderCount))
	for i := range leaders {
		leaders[i] = infiniteStatusLeader{ranked[i], i + 1}
	}
	arena.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(struct {
		Players   int                    `json:"players"`
		TankCount int                    `json:"tankCount"`
		Capacity  int                    `json:"capacity"`
		Leaders   []infiniteStatusLeader `json:"leaders"`
	}{players, tankCount, infiniteCapacity, leaders})
}
