package main

import (
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const chatMaxRunes = 280
const chatHistoryLimit = 60

// A room message is plain text, attributed by the server to a member's socket.
// Side is retained only for filtering opponent-chat history and is never sent.
type ChatMessage struct {
	ID         uint64 `json:"id"`
	Member     uint64 `json:"member"`
	Name       string `json:"name"`
	Text       string `json:"text"`
	Spectating bool   `json:"spectating"`
	Team       int    `json:"team"`
	At         int64  `json:"at"`
	Side       int    `json:"-"`
}

func matchChatSide(r *Room, p *Player) (int, bool) {
	if r == nil || r.Match == nil || p == nil {
		return 0, false
	}
	if !p.Spectating {
		if r.Match.Definition.TeamSize == 0 {
			return p.ID + 1, true // FFA: every pilot is a distinct side.
		}
		return p.Team, p.Team > 0
	}
	if p.Return == nil || p.Return.Home == nil {
		return 0, false
	}
	for _, active := range r.Players {
		if active == nil || active.Return == nil || active.Return.Home != p.Return.Home {
			continue
		}
		if r.Match.Definition.TeamSize == 0 {
			return active.ID + 1, true
		}
		return active.Team, active.Team > 0
	}
	return 0, false
}

func opponentChatVisible(r *Room, viewer *Player, msg ChatMessage) bool {
	if viewer == nil || msg.Side <= 0 {
		return false
	}
	if viewer.Member == msg.Member {
		return true
	}
	side, ok := matchChatSide(r, viewer)
	return ok && side != msg.Side
}

func boundedChat(history []ChatMessage, msg ChatMessage) []ChatMessage {
	if len(history) < chatHistoryLimit {
		return append(history, msg)
	}
	copy(history, history[1:])
	history[len(history)-1] = msg
	return history
}

func (h *Hub) sendChatHistory(c *Client, r *Room) {
	history := r.Chat
	if history == nil {
		history = []ChatMessage{}
	}
	c.enqueue(map[string]any{"type": "chat_history", "room": r.Code, "channel": "room", "messages": history})
	if r.Match == nil || c.player == nil {
		return
	}
	opponents := make([]ChatMessage, 0, len(r.OpponentChat))
	for _, msg := range r.OpponentChat {
		if opponentChatVisible(r, c.player, msg) {
			opponents = append(opponents, msg)
		}
	}
	c.enqueue(map[string]any{"type": "chat_history", "room": r.Code, "channel": "opponent", "messages": opponents})
}

func (h *Hub) chat(c *Client, m clientMessage, now time.Time) {
	channel := m.Channel
	if channel == "" {
		channel = "room"
	}
	fail := func(code, text string) {
		v := roomError(code, text)
		v["action"] = "chat"
		v["channel"] = channel
		c.enqueue(v)
	}
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || !r.contains(p) {
		fail("not_joined", "Join an online room before chatting.")
		return
	}
	if channel != "room" && channel != "opponent" {
		fail("bad_chat_channel", "Choose a valid chat channel.")
		return
	}
	var side int
	if channel == "opponent" {
		var ok bool
		side, ok = matchChatSide(r, p)
		if !ok {
			fail("chat_unavailable", "Opponent chat is available only during a matchmaking match.")
			return
		}
	}
	text := strings.TrimSpace(m.Text)
	if !utf8.ValidString(text) || text == "" || utf8.RuneCountInString(text) > chatMaxRunes {
		fail("bad_chat", "Use 1–280 characters per message.")
		return
	}
	visible := false
	for _, v := range text {
		if unicode.IsControl(v) || v == '\u2028' || v == '\u2029' {
			fail("bad_chat", "Chat messages must be on one line.")
			return
		}
		if !unicode.IsSpace(v) && !unicode.Is(unicode.Cf, v) {
			visible = true
		}
	}
	if !visible {
		fail("bad_chat", "Please type a visible message.")
		return
	}
	// Four-message burst, then one message per second. Both channels share the
	// same member-owned budget so switching channels cannot bypass rate limits.
	if p.ChatAt.IsZero() {
		p.ChatTokens = 4
	} else {
		elapsed := now.Sub(p.ChatAt).Seconds()
		if elapsed > 0 {
			p.ChatTokens = clamp(p.ChatTokens+elapsed, 0, 4)
		}
	}
	p.ChatAt = now
	if p.ChatTokens < 1 {
		fail("chat_rate", "You're sending messages too quickly. Please slow down.")
		return
	}
	p.ChatTokens--

	var id uint64
	if channel == "opponent" {
		r.NextOpponentChat++
		id = r.NextOpponentChat
	} else {
		r.NextChat++
		id = r.NextChat
	}
	msg := ChatMessage{ID: id, Member: p.Member, Name: p.Name, Text: text, Spectating: p.Spectating, Team: p.Team, At: now.UnixMilli(), Side: side}
	if channel == "opponent" {
		r.OpponentChat = boundedChat(r.OpponentChat, msg)
	} else {
		r.Chat = boundedChat(r.Chat, msg)
	}
	r.LastAction = now
	packet := map[string]any{"type": "chat", "room": r.Code, "channel": channel, "message": msg}
	data, ok := encodePacket(packet)
	if !ok {
		return
	}
	if channel == "room" {
		for _, member := range r.members() {
			if member.Client != nil {
				member.Client.enqueueBytes(data)
			}
		}
		return
	}
	// Opponent chat is deliberately not a team channel: only the sender and the
	// opposing matchmaking side receive it. A room can have two local pilots on
	// one socket, so deduplicate without allocating a map on every chat message.
	var sent [maxTanks + maxSpectators]*Client
	n := 0
	for _, member := range r.members() {
		if member.Client == nil || !opponentChatVisible(r, member, msg) {
			continue
		}
		duplicate := false
		for i := 0; i < n; i++ {
			if sent[i] == member.Client {
				duplicate = true
				break
			}
		}
		if duplicate {
			continue
		}
		sent[n] = member.Client
		n++
		member.Client.enqueueBytes(data)
	}
}
