package main

import "errors"

// Room credentials expire with a seat. The durable owner bearer only controls
// callsign claims and is copied privately into welcomes, never room snapshots.
type onlineRoomIdentity struct {
	token  string
	names  []string
	action string
}

// Called while Hub.mu is held. The registry never calls back into Hub/Infinity.
func (h *Hub) claimRoomCallsigns(c *Client, action, token string, names []string) (string, bool) {
	owner, err := h.callsigns.claim(token, names)
	if err == nil {
		return owner, true
	}
	var conflict *callsignConflictError
	var message map[string]any
	switch {
	case errors.As(err, &conflict):
		message = roomError("callsign_taken", conflict.Error())
		message["conflicts"] = conflict.Conflicts
	case errors.Is(err, errOnlineOwnerInvalid):
		message = roomError("public_resume_invalid", "The saved online identity is no longer available. Choose another callsign or restore its owner identity.")
	default:
		message = roomError("server_error", "Could not save your online callsign. Try again shortly.")
	}
	message["action"] = action
	c.enqueue(message)
	return "", false
}

func roomControllerNames(r *Room, controller, changed *Player, name string) []string {
	primary := controller.Name
	if changed == controller {
		primary = name
	}
	names := []string{primary}
	for _, p := range r.members() {
		if p.Kind != "local" || p.Controller != controller && (p.Controller != nil || p.Owner != controller.ID) {
			continue
		}
		local := p.Name
		if p == changed {
			local = name
		}
		names = append(names, local)
	}
	return names
}
