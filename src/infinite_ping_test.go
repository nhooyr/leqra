package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
	"net/http/httptest"
	"testing"
)

func readInfinityPingClose(t *testing.T, reader *bufio.Reader) uint16 {
	t.Helper()
	var header [2]byte
	if _, err := io.ReadFull(reader, header[:]); err != nil {
		t.Fatal(err)
	}
	if header[0] != 136 || header[1] < 2 || header[1] >= 126 {
		t.Fatalf("expected close frame, got %v", header)
	}
	body := make([]byte, int(header[1]))
	if _, err := io.ReadFull(reader, body); err != nil {
		t.Fatal(err)
	}
	return binary.BigEndian.Uint16(body[:2])
}

func TestInfinityApplicationPingEchoesRoundTripTimestampAndKeepsInput(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	c, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": "RTT"}, false)
	var welcome struct {
		Type string `json:"type"`
		ID   int    `json:"id"`
	}
	readInfinitePacket(t, reader, &welcome)
	if welcome.Type != "welcome" {
		t.Fatalf("join failed: %+v", welcome)
	}
	for index, stamp := range []float64{0, 1234.56789, 1e100} {
		// A following pong is a reliable barrier proving the preceding input
		// was accepted by the same joined read loop.
		input := []byte(fmt.Sprintf(`{"type":"input","seq":%d,"forward":true}`, index+1))
		if _, err := c.Write(maskedFrame(1, true, input)); err != nil {
			t.Fatal(err)
		}
		ping := []byte(fmt.Sprintf(`{"type":"ping","t":%.17g}`, stamp))
		if _, err := c.Write(maskedFrame(1, true, ping)); err != nil {
			t.Fatal(err)
		}
		var pong struct {
			Type string  `json:"type"`
			T    float64 `json:"t"`
		}
		readInfinitePacket(t, reader, &pong)
		if pong.Type != "pong" || pong.T != stamp {
			t.Fatalf("timestamp was not echoed exactly: %+v, want %g", pong, stamp)
		}
		app.infinite.public.mu.Lock()
		var accepted bool
		for _, pilot := range app.infinite.public.pilots {
			if pilot.ID == welcome.ID {
				accepted = pilot.input.Seq == uint64(index+1) && pilot.input.Forward
			}
		}
		app.infinite.public.mu.Unlock()
		if !accepted {
			t.Fatal("ping handling disrupted joined input")
		}
	}
}

func TestInfinityApplicationPingRejectsInvalidTimestampsAndExcessRate(t *testing.T) {
	for _, tc := range []struct {
		name, packet string
		code         uint16
	}{
		{"missing", `{"type":"ping"}`, 1008},
		{"null", `{"type":"ping","t":null}`, 1008},
		{"string", `{"type":"ping","t":"123"}`, 1007},
		{"nonfinite", `{"type":"ping","t":1e999}`, 1007},
		{"excess rate", `{"type":"ping","t":9}`, 1008},
	} {
		t.Run(tc.name, func(t *testing.T) {
			app := newApp(4, nil)
			t.Cleanup(app.infinite.close)
			server := httptest.NewServer(app.handler())
			t.Cleanup(server.Close)
			c, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version}, false)
			var welcome map[string]any
			readInfinitePacket(t, reader, &welcome)
			if tc.name == "excess rate" {
				for range 8 {
					if _, err := c.Write(maskedFrame(1, true, []byte(`{"type":"ping","t":1}`))); err != nil {
						t.Fatal(err)
					}
					var pong map[string]any
					readInfinitePacket(t, reader, &pong)
					if pong["type"] != "pong" {
						t.Fatalf("allowed ping was rejected: %v", pong)
					}
				}
			}
			if _, err := c.Write(maskedFrame(1, true, []byte(tc.packet))); err != nil {
				t.Fatal(err)
			}
			if code := readInfinityPingClose(t, reader); code != tc.code {
				t.Fatalf("close code = %d, want %d", code, tc.code)
			}
		})
	}
}

func TestInfinityApplicationPingCannotReplaceJoin(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	_, reader := dialInfinite(t, server.URL, map[string]string{"type": "ping", "version": version}, false)
	var reply map[string]any
	readInfinitePacket(t, reader, &reply)
	if reply["type"] != "error" {
		t.Fatalf("unjoined ping was accepted: %v", reply)
	}
	if code := readInfinityPingClose(t, reader); code != 1008 {
		t.Fatalf("unjoined ping close code = %d", code)
	}
}
