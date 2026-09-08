package main

import (
	"bufio"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestWebSocketConnectionHeaderFields(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if ws, err := upgradeWS(w, r, nil); err == nil {
			ws.close()
		}
	}))
	defer server.Close()
	host := strings.TrimPrefix(server.URL, "http://")
	for _, tc := range []struct {
		name, fields string
		status       int
	}{
		{"single", "Connection: Upgrade\r\n", 101},
		{"combined", "Connection: keep-alive, uPgRaDe\r\n", 101},
		{"upgrade last", "Connection: keep-alive\r\nConnection: Upgrade\r\n", 101},
		{"upgrade first", "Connection: Upgrade\r\nConnection: keep-alive\r\n", 101},
		{"token in later list", "Connection: keep-alive\r\nConnection: other, upgrade\r\n", 101},
		{"missing", "", 400},
		{"no token", "Connection: keep-alive\r\nConnection: close\r\n", 400},
		{"substring", "Connection: keep-alive\r\nConnection: not-upgrade\r\n", 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			conn, err := net.Dial("tcp", host)
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
				t.Fatal(err)
			}
			_, err = fmt.Fprintf(conn, "GET /ws HTTP/1.1\r\nHost: %s\r\n%sUpgrade: websocket\r\nOrigin: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", host, tc.fields, server.URL)
			if err != nil {
				t.Fatal(err)
			}
			response, err := http.ReadResponse(bufio.NewReader(conn), nil)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			if response.StatusCode != tc.status {
				t.Fatalf("handshake status = %d, want %d", response.StatusCode, tc.status)
			}
		})
	}
}
