package main

import (
	"errors"
	"time"
)

// Room credentials expire with a seat. The durable owner bearer only controls
// callsign claims and is copied privately into welcomes, never room snapshots.
type onlineRoomIdentity struct {
	token       string
	names       []string
	action      string
	localToken  string
	localNew    bool
	independent bool
}

// Called while Hub.mu is held. The registry never calls back into Hub/Infinity.
func (h *Hub) claimRoomCallsigns(c *Client, action, token string, names []string) (string, bool) {
	owner, err := h.callsigns.claim(token, names)
	if err == nil {
		return owner, true
	}
	h.accountClaimError(c, action, err)
	return "", false
}

func (h *Hub) accountClaimError(c *Client, action string, err error) {
	var conflict *callsignConflictError
	var message map[string]any
	switch {
	case errors.As(err, &conflict):
		message = roomError("callsign_taken", conflict.Error())
		message["conflicts"] = conflict.Conflicts
	case errors.Is(err, errOnlineOwnerInvalid):
		message = roomError("public_resume_invalid", "The saved online identity is no longer available. Choose another callsign or restore its owner identity.")
	case errors.Is(err, errOnlineOwnerRevoked):
		message = accountRevokedPacket()
	case errors.Is(err, errSameSeatAccount):
		message = roomError("account_seat_conflict", errSameSeatAccount.Error())
	case errors.Is(err, errNewAccountKeyInvalid):
		message = roomError("local_account_required", "Save a new P2 account key before going online.")
	default:
		message = roomError("server_error", "Could not save your online callsign. Try again shortly.")
	}
	message["action"] = action
	var seat *seatAccountError
	if errors.As(err, &seat) {
		message["seat"] = seat.seat
	}
	c.enqueue(message)
}

func (h *Hub) claimNewRoomAccounts(c *Client, action, token, localToken string, localNew, independent bool, names []string) (string, bool) {
	if !independent && localToken == "" {
		return h.claimRoomCallsigns(c, action, token, names)
	}
	requests := []accountSeatClaim{{token: token, name: names[0]}}
	if len(names) > 1 {
		requests = append(requests, accountSeatClaim{token: localToken, name: names[1], newAccount: localNew, transferFrom: token})
	}
	accounts, err := h.callsigns.claimSeatAccounts(requests, nil)
	if err != nil {
		h.accountClaimError(c, action, err)
		return "", false
	}
	c.independentAccounts = true
	c.localOwnerToken = ""
	if len(accounts) > 1 {
		c.localOwnerToken = accounts[1].token
		if accounts[1].fresh {
			var current *Player
			if c.room != nil {
				current = roomLocalController(c.room, c.player)
			}
			h.expireLegacyLocalClaims(token, current)
		}
	}
	return accounts[0].token, true
}

func (h *Hub) expireLegacyLocalClaims(token string, except *Player) {
	for _, room := range h.rooms {
		for _, local := range room.members() {
			if local == except || local.Kind != "local" || local.PublicToken != "" {
				continue
			}
			owner := local.Controller
			if owner == nil {
				owner = room.member(local.Owner)
			}
			if owner != nil && owner.PublicToken == token {
				if controller := owner.Client; controller != nil {
					h.detachController(room, owner, time.Now())
					stopAccountTransport(controller, map[string]any{"type": "error", "code": "session_replaced", "seat": 1, "message": "P2 moved to an independent account on another device. This connection has signed out."})
				}
				h.expirePlayer(room, local.ID)
				h.broadcastRoom(room)
			}
		}
	}
}

func (h *Hub) resumeControllerAccounts(c *Client, r *Room, owner *Player, identity onlineRoomIdentity) bool {
	local := roomLocalController(r, owner)
	if local == nil {
		return true
	}
	if local.PublicToken != "" {
		if identity.localToken != "" && identity.localToken != local.PublicToken {
			hash, valid := publicTokenHash(identity.localToken)
			h.callsigns.mu.Lock()
			unused := valid && !h.callsigns.owners[hash] && !h.callsigns.revoked[hash]
			h.callsigns.mu.Unlock()
			if !identity.localNew || !unused {
				h.accountClaimError(c, "join", &seatAccountError{1, errSameSeatAccount})
				return false
			}
		}
		c.independentAccounts, c.localOwnerToken = true, local.PublicToken
		return true
	}
	if !identity.independent && identity.localToken == "" {
		return true
	}
	accounts, err := h.callsigns.claimSeatAccounts([]accountSeatClaim{{token: owner.PublicToken, name: owner.Name}, {token: identity.localToken, name: local.Name, newAccount: identity.localNew, transferFrom: owner.PublicToken}}, nil)
	if err != nil {
		h.accountClaimError(c, "join", err)
		return false
	}
	local.PublicToken = accounts[1].token
	c.localOwnerToken = accounts[1].token
	c.independentAccounts = true
	h.expireLegacyLocalClaims(owner.PublicToken, local)
	return true
}

func roomLocalController(r *Room, controller *Player) *Player {
	for _, p := range r.members() {
		if p.Kind == "local" && (p.Controller == controller || p.Controller == nil && p.Owner == controller.ID) {
			return p
		}
	}
	return nil
}

func (h *Hub) claimControllerCallsigns(c *Client, action string, r *Room, controller, changed *Player, name string) (string, bool) {
	names := roomControllerNames(r, controller, changed, name)
	local := roomLocalController(r, controller)
	if local == nil || local.PublicToken == "" || local.PublicToken == controller.PublicToken {
		return h.claimRoomCallsigns(c, action, controller.PublicToken, names)
	}
	accounts, err := h.callsigns.claimSeatAccounts([]accountSeatClaim{{token: controller.PublicToken, name: names[0]}, {token: local.PublicToken, name: names[1]}}, nil)
	if err != nil {
		h.accountClaimError(c, action, err)
		return "", false
	}
	return accounts[0].token, true
}

// Credentials are sent only to this room token's controller, never the roster.
func (h *Hub) sendControllerAccounts(c *Client) {
	if c.player == nil || c.room == nil {
		return
	}
	packet := map[string]any{"type": "identity", "id": c.player.ID, "member": c.player.Member, "spectating": c.player.Spectating, "publicToken": c.player.PublicToken}
	if local := roomLocalController(c.room, c.player); local != nil {
		packet["localId"], packet["localMember"] = local.ID, local.Member
		if local.PublicToken != "" {
			packet["localPublicToken"] = local.PublicToken
		}
	}
	c.enqueue(packet)
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
