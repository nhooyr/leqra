package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func maskedFrame(op byte, fin bool, data []byte) []byte {
	first := op
	if fin {
		first |= 128
	}
	out := []byte{first}
	n := len(data)
	if n < 126 {
		out = append(out, 128|byte(n))
	} else {
		out = append(out, 128|126, byte(n>>8), byte(n))
	}
	mask := []byte{21, 33, 57, 85}
	out = append(out, mask...)
	for i, b := range data {
		out = append(out, b^mask[i%4])
	}
	return out
}
func parseFrames(t *testing.T, frames []byte) ([]byte, error) {
	t.Helper()
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()
	c := &wsConn{conn: server, reader: bufio.NewReader(server), frameWindow: time.Now()}
	done := make(chan struct{})
	go func() { defer close(done); _, _ = client.Write(frames) }()
	data, err := c.readMessage()
	_ = server.Close()
	<-done
	return data, err
}
func TestWebSocketTextAndFragmentation(t *testing.T) {
	text := []byte(`{"type":"ping","t":42}`)
	frames := append(maskedFrame(1, false, text[:5]), maskedFrame(0, true, text[5:])...)
	for _, f := range [][]byte{maskedFrame(1, true, text), frames} {
		got, err := parseFrames(t, f)
		if err != nil || !bytes.Equal(got, text) {
			t.Fatalf("read %q error %v", got, err)
		}
	}
	large := bytes.Repeat([]byte("a"), 400)
	got, err := parseFrames(t, maskedFrame(1, true, large))
	if err != nil || len(got) != 400 {
		t.Fatal("extended length failed")
	}
}
func TestWebSocketRejectsInvalidFrames(t *testing.T) {
	tests := []struct {
		name string
		data []byte
		code uint16
	}{
		{"unmasked", []byte{129, 2, '{', '}'}, 1002},
		{"reserved", []byte{193, 128}, 1002},
		{"continuation", maskedFrame(0, true, []byte("x")), 1002},
		{"nested", append(maskedFrame(1, false, []byte("a")), maskedFrame(1, true, []byte("b"))...), 1002},
		{"binary", maskedFrame(2, true, []byte("x")), 1003},
		{"utf8", maskedFrame(1, true, []byte{255}), 1007},
		{"oversize", maskedFrame(1, true, bytes.Repeat([]byte("a"), maxMessage+1)), 1009},
		{"fragment-limit", append(maskedFrame(1, false, bytes.Repeat([]byte("a"), maxMessage/2+1)), maskedFrame(0, true, bytes.Repeat([]byte("b"), maxMessage/2+1))...), 1009},
		{"fragmented-ping", maskedFrame(9, false, []byte("x")), 1002},
		{"long-control", maskedFrame(9, true, bytes.Repeat([]byte("x"), 126)), 1002},
		{"invalid-close", maskedFrame(8, true, []byte{3}), 1002},
		{"reserved-close", maskedFrame(8, true, []byte{3, 237}), 1002},
		{"close-utf8", maskedFrame(8, true, []byte{3, 232, 255}), 1007},
		{"opcode", maskedFrame(3, true, []byte("x")), 1002},
		{"nonminimal-length", []byte{129, 254, 0, 1, 0, 0, 0, 0, 0}, 1002},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parseFrames(t, tt.data)
			var e *wsError
			if !errors.As(err, &e) || e.code != tt.code {
				t.Fatalf("got %v, expected %d", err, tt.code)
			}
		})
	}
}
func TestWebSocketPingInterleavesText(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()
	c := &wsConn{conn: server, reader: bufio.NewReader(server), frameWindow: time.Now()}
	done := make(chan error, 1)
	go func() {
		if _, err := client.Write(maskedFrame(9, true, []byte("hello"))); err != nil {
			done <- err
			return
		}
		pong := make([]byte, 7)
		if _, err := io.ReadFull(client, pong); err != nil {
			done <- err
			return
		}
		if pong[0] != 138 || string(pong[2:]) != "hello" {
			done <- errors.New("invalid pong")
			return
		}
		_, err := client.Write(maskedFrame(1, true, []byte("ok")))
		done <- err
	}()
	got, err := c.readMessage()
	if err != nil || string(got) != "ok" {
		t.Fatal("text after ping failed")
	}
	if err = <-done; err != nil {
		t.Fatal(err)
	}
}
func TestWebSocketWritesExtendedLength(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()
	c := &wsConn{conn: server}
	data := bytes.Repeat([]byte("a"), 70000)
	done := make(chan error, 1)
	go func() { done <- c.writeFrame(1, data) }()
	var header [10]byte
	if _, err := io.ReadFull(client, header[:]); err != nil {
		t.Fatal(err)
	}
	if header[0] != 129 || header[1] != 127 || binary.BigEndian.Uint64(header[2:]) != 70000 {
		t.Fatal("invalid 64-bit frame header")
	}
	got := make([]byte, 70000)
	_, _ = io.ReadFull(client, got)
	if !bytes.Equal(data, got) {
		t.Fatal("payload changed")
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}
func TestWebSocketOrigins(t *testing.T) {
	for _, tt := range []struct {
		origin  string
		allowed bool
	}{{"http://game.test", true}, {"https://game.test", true}, {"http://evil.test", false}, {"null", false}, {"", false}, {"https://evil.test/path", false}, {"https://friend.test", true}} {
		r := httptest.NewRequest("GET", "http://game.test/ws", nil)
		r.Header.Set("Origin", tt.origin)
		got := validOrigin(r, []string{"https://friend.test"})
		if got != tt.allowed {
			t.Errorf("origin %q got %v", tt.origin, got)
		}
	}
}
func TestHTTPAndUpgradeValidation(t *testing.T) {
	app := newApp(4, nil)
	h := app.handler()
	for _, tt := range []struct {
		path   string
		status int
	}{{"/", 200}, {"/api/config", 200}, {"/healthz", 200}, {"/assets/v" + version + "/game.js", 200}, {"/game.js", 404}, {"/go.mod", 404}, {"/ws", 400}} {
		r := httptest.NewRequest("GET", "http://game.test"+tt.path, nil)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tt.status {
			t.Errorf("%s: %d", tt.path, w.Code)
		}
		if w.Header().Get("X-Content-Type-Options") != "nosniff" {
			t.Fatal("security headers missing")
		}
	}
	r := httptest.NewRequest("GET", "http://game.test/ws", nil)
	r.Header.Set("Connection", "Upgrade")
	r.Header.Set("Upgrade", "websocket")
	r.Header.Set("Sec-WebSocket-Version", "13")
	r.Header.Set("Origin", "http://evil.test")
	r.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 403 {
		t.Fatal("cross-origin upgrade accepted")
	}
	r.Header.Set("Origin", "http://game.test")
	r.Header.Set("Sec-WebSocket-Version", "12")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 426 {
		t.Fatal("wrong version accepted")
	}
	r.Header.Set("Sec-WebSocket-Version", "13")
	r.Header.Set("Sec-WebSocket-Key", "bad")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 400 {
		t.Fatal("bad key accepted")
	}
}
func TestRealWebSocketHandshake(t *testing.T) {
	app := newApp(4, nil)
	srv := httptest.NewServer(app.handler())
	defer srv.Close()
	defer app.hub.close()
	host := strings.TrimPrefix(srv.URL, "http://")
	c, err := net.Dial("tcp", host)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(3 * time.Second))
	request := "GET /ws HTTP/1.1\r\nHost: " + host + "\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nOrigin: " + srv.URL + "\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	_, _ = c.Write([]byte(request))
	r := bufio.NewReader(c)
	line, _ := r.ReadString('\n')
	if !strings.Contains(line, "101") {
		t.Fatal(line)
	}
	headers := ""
	for {
		line, err = r.ReadString('\n')
		if err != nil {
			t.Fatal(err)
		}
		if line == "\r\n" {
			break
		}
		headers += line
	}
	if !strings.Contains(headers, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") {
		t.Fatal("incorrect accept hash")
	}
	readFrame := func() []byte {
		var h [2]byte
		if _, err := io.ReadFull(r, h[:]); err != nil {
			t.Fatal(err)
		}
		if h[0] != 129 {
			t.Fatalf("expected text frame, opcode byte=%d", h[0])
		}
		n := int(h[1] & 0x7f)
		if n == 126 {
			var ext [2]byte
			_, _ = io.ReadFull(r, ext[:])
			n = int(binary.BigEndian.Uint16(ext[:]))
		}
		payload := make([]byte, n)
		_, _ = io.ReadFull(r, payload)
		return payload
	}
	hello := readFrame()
	if !bytes.Contains(hello, []byte(`"type":"server_hello"`)) || !bytes.Contains(hello, []byte(`"version":"`+version+`"`)) {
		t.Fatal(string(hello))
	}
	_, _ = c.Write(maskedFrame(1, true, []byte(`{"type":"client_hello","version":"`+version+`","protocol":1}`)))
	_, _ = c.Write(maskedFrame(1, true, []byte(`{"type":"create","name":"RAW CLIENT"}`)))
	foundWelcome := false
	for i := 0; i < 4; i++ {
		payload := readFrame()
		if bytes.Contains(payload, []byte(`"type":"welcome"`)) {
			foundWelcome = true
			break
		}
	}
	if !foundWelcome {
		t.Fatal("no welcome after version handshake")
	}
}
