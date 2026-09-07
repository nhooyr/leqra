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
// Names/roles are captured at send time. No tokens or private addresses are sent.
type ChatMessage struct {
	ID         uint64 `json:"id"`
	Member     uint64 `json:"member"`
	Name       string `json:"name"`
	Text       string `json:"text"`
	Spectating bool   `json:"spectating"`
	Team       int    `json:"team"`
	At         int64  `json:"at"`
}

func (h *Hub) sendChatHistory(c *Client, r *Room) {
	history := r.Chat
	if history == nil {
		history = []ChatMessage{}
	}
	c.enqueue(map[string]any{"type": "chat_history", "room": r.Code, "messages": history})
}

func (h *Hub) chat(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) { v := roomError(code, text); v["action"] = "chat"; c.enqueue(v) }
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || !r.contains(p) {
		fail("not_joined", "Join an online room before chatting.")
		return
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
	// Four-message burst, then one message per second. Member-owned so reconnect
	// and spectating cannot reset the budget. Invalid messages cost no tokens.
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
	r.NextChat++
	msg := ChatMessage{ID: r.NextChat, Member: p.Member, Name: p.Name, Text: text, Spectating: p.Spectating, Team: p.Team, At: now.UnixMilli()}
	r.Chat = append(r.Chat, msg)
	if len(r.Chat) > chatHistoryLimit {
		copy(r.Chat, r.Chat[len(r.Chat)-chatHistoryLimit:])
		r.Chat = r.Chat[:chatHistoryLimit]
	}
	r.LastAction = now
	packet := map[string]any{"type": "chat", "room": r.Code, "message": msg}
	// Serialize once for the whole room; chat never rides in 30 Hz state snapshots.
	data, ok := encodePacket(packet)
	if !ok {
		return
	}
	for _, member := range r.members() {
		if member.Client != nil {
			member.Client.enqueueBytes(data)
		}
	}
}
