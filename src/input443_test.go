package main

import "testing"

func TestInput443StaleLocalSwapPacketCannotPoisonOtherPilot(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		name := "primary_to_local"
		if reverse {
			name = "local_to_primary"
		}
		t.Run(name, func(t *testing.T) {
			h, cs, r := makeRoom(t, 2)
			c := cs[0]
			p1 := c.player
			p2 := addSeat(t, h, c, "local", "", 1)
			action(t, h, c, map[string]any{"type": "spectate", "target": p2.ID, "member": p2.Member, "spectating": true})
			active, incoming := p1, p2
			if reverse {
				swap33(t, h, c, p1, p2)
				active, incoming = p2, p1
			}
			r.Game.startMatch(r.Players)
			oldSeat := active.ID
			// This command was sent by the old pilot before the host's role change
			// reached the browser, but reaches the server after the seat exchange.
			inFlight := map[string]any{"type": "input", "room": r.Code, "player": oldSeat, "member": active.Member, "seq": 5001, "forward": true, "fire": true}
			swap33(t, h, c, active, incoming)
			if incoming.ID != oldSeat || incoming.Spectating || !active.Spectating {
				t.Fatal("fixture did not exchange the controller's two pilots")
			}
			action(t, h, c, inFlight)
			if incoming.Input.Seq != 0 || incoming.Input.Forward || incoming.FirePending {
				t.Fatalf("old pilot's packet entered the replacement's channel: %+v, pending=%v", incoming.Input, incoming.FirePending)
			}
			action(t, h, c, map[string]any{"type": "input", "room": r.Code, "player": incoming.ID, "member": incoming.Member, "seq": 31, "right": true, "fire": true})
			if incoming.Input.Seq != 31 || !incoming.Input.Right || !incoming.FirePending {
				t.Fatal("replacement's current input was blocked by the old pilot's sequence")
			}
			// A delayed old release must not cancel the new pilot's held controls.
			inFlight["seq"], inFlight["forward"], inFlight["fire"] = 5002, false, false
			action(t, h, c, inFlight)
			if incoming.Input.Seq != 31 || !incoming.Input.Right || !incoming.Input.Fire {
				t.Fatal("old pilot's release cancelled the replacement's controls")
			}
		})
	}
}

func TestInput443MemberValidationRetainsLegacyAndOwnerGuards(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	c := cs[0]
	p2 := addSeat(t, h, c, "local", "", 1)
	for _, pilot := range []*Player{c.player, p2} {
		packet := map[string]any{"type": "input", "room": r.Code, "player": pilot.ID, "member": cs[1].player.Member, "seq": 100, "fire": true}
		action(t, h, c, packet)
		if pilot.Input.Seq != 0 || pilot.FirePending {
			t.Fatal("wrong member identity changed input")
		}
		delete(packet, "member")
		packet["seq"] = 1
		action(t, h, c, packet)
		if pilot.Input.Seq != 1 || !pilot.FirePending {
			t.Fatal("member-less legacy input stopped working")
		}
		packet["member"], packet["seq"], packet["fire"] = pilot.Member, 2, false
		action(t, h, c, packet)
		if pilot.Input.Seq != 2 || pilot.Input.Fire {
			t.Fatal("current identity could not release input")
		}
		packet["seq"], packet["fire"] = 3, true
		action(t, h, cs[1], packet)
		if !hasError(cs[1], "not_owned") || pilot.Input.Seq != 2 {
			t.Fatal("public member identity bypassed controller ownership")
		}
	}
}
