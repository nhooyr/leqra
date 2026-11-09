package main

import (
	"crypto/sha256"
	"time"
)

const maxResumeRoutes = 1024

// Called with Hub.mu held. Routes follow the destination room across renames.
func (h *Hub) resumedRoom(code, token string, now time.Time) *Room {
	route, ok := h.resumeRoutes[resumeRouteKey{code, sha256.Sum256([]byte(token))}]
	if ok && now.Before(route.Until) && route.Room != nil && h.rooms[route.Room.Code] == route.Room {
		return route.Room
	}
	return nil
}

// Room renames and matchmaking returns share the same bounded reconnect cache.
// Called with Hub.mu held. Refreshing a route never evicts another credential.
func (h *Hub) rememberResumeRoute(code, token string, room *Room, now time.Time) {
	if token == "" {
		return
	}
	if h.resumeRoutes == nil {
		h.resumeRoutes = make(map[resumeRouteKey]resumeRoute)
	}
	key := resumeRouteKey{code, sha256.Sum256([]byte(token))}
	if _, exists := h.resumeRoutes[key]; !exists && len(h.resumeRoutes) >= maxResumeRoutes {
		// Recover stale capacity before discarding a still-valid reconnect.
		for oldKey, route := range h.resumeRoutes {
			if !now.Before(route.Until) || route.Room == nil || h.rooms[route.Room.Code] != route.Room {
				delete(h.resumeRoutes, oldKey)
			}
		}
		if len(h.resumeRoutes) >= maxResumeRoutes {
			var oldest resumeRouteKey
			var earliest time.Time
			for oldKey, route := range h.resumeRoutes {
				if earliest.IsZero() || route.Until.Before(earliest) {
					oldest, earliest = oldKey, route.Until
				}
			}
			delete(h.resumeRoutes, oldest)
		}
	}
	h.resumeRoutes[key] = resumeRoute{room, now.Add(reconnectGrace)}
}
