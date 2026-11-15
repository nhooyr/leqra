package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"testing"
	"time"
)

func TestWebSocketDeflateOffer(t *testing.T) {
	for _, tt := range []struct {
		header string
		want   bool
	}{
		{"permessage-deflate", true},
		{"other, permessage-deflate; client_max_window_bits", true},
		{`permessage-deflate; client_max_window_bits="12"; server_no_context_takeover`, true},
		{"permessage-deflate; server_max_window_bits=10, permessage-deflate", true},
		{"permessage-deflate; server_max_window_bits=10", false},
		{"permessage-deflate; unknown", false},
		{"permessage-deflate; client_no_context_takeover=1", false},
		{"permessage-deflate; client_max_window_bits; client_max_window_bits=10", false},
		{"permessage-deflate; client_max_window_bits=7", false},
		{"x-permessage-deflate", false},
	} {
		if got := acceptsSnapshotDeflate([]string{"unrelated", tt.header}); got != tt.want {
			t.Errorf("offer %q: got %v, want %v", tt.header, got, tt.want)
		}
	}
}

func TestWebSocketDeflateBoundsAndFragmentation(t *testing.T) {
	// Known independent compressed payload from RFC 7692 section 7.2.3.1.
	hello := []byte{0xf2, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00}
	textFrame := maskedFrame(wsCompressed|1, true, hello)
	fragmented := append(maskedFrame(wsCompressed|1, false, hello[:3]), maskedFrame(0, true, hello[3:])...)
	for _, frame := range [][]byte{textFrame, fragmented} {
		got, err := parseFramesWithDeflate(t, frame, true)
		if err != nil || string(got) != "Hello" {
			t.Fatalf("compressed text %q: %v", got, err)
		}
	}
	checkError := func(frame []byte, negotiate bool, code uint16) {
		t.Helper()
		_, err := parseFramesWithDeflate(t, frame, negotiate)
		var wireErr *wsError
		if !errors.As(err, &wireErr) || wireErr.code != code {
			t.Fatalf("got %v, want close code %d", err, code)
		}
	}
	checkError(textFrame, false, 1002)
	checkError(maskedFrame(wsCompressed|9, true, hello), true, 1002)
	checkError(append(maskedFrame(wsCompressed|1, false, hello[:3]), maskedFrame(wsCompressed, true, hello[3:])...), true, 1002)
	checkError(maskedFrame(wsCompressed|1, true, []byte{0xff}), true, 1007)
	for _, test := range []struct {
		data []byte
		code uint16
	}{
		{bytes.Repeat([]byte("a"), maxMessage+1), 1009},
		{bytes.Repeat([]byte{0xff}, maxMessage), 1007},
	} {
		frame := compressSnapshot(test.data)
		if !frame.compressed || len(frame.data) > maxMessage {
			t.Fatal("test needs a compact compressed frame")
		}
		checkError(maskedFrame(wsCompressed|1, true, frame.data), true, test.code)
	}
	exact := bytes.Repeat([]byte("a"), maxMessage)
	frame := compressSnapshot(exact)
	if got, err := parseFramesWithDeflate(t, maskedFrame(wsCompressed|1, true, frame.data), true); err != nil || !bytes.Equal(got, exact) {
		t.Fatalf("valid compressed message at limit: %d bytes, %v", len(got), err)
	}
}

func TestSnapshotSharesOneJSONBufferAndKeepsWorldReliable(t *testing.T) {
	h := newHub(1)
	players := testPlayers(4)
	g := newGame(42)
	g.startMatch(players)
	r := &Room{Game: g, Players: players}
	for _, p := range players {
		if p == nil {
			continue
		}
		p.Client = &Client{send: make(chan []byte, 1), updates: make(chan snapshotFrame, 1), done: make(chan struct{}), mapGeneration: g.Generation}
	}
	players[3].Client.mapGeneration = -1
	h.broadcastState(r)
	plain := <-players[0].Client.updates
	second := <-players[1].Client.updates
	shared := <-players[2].Client.updates
	world := <-players[3].Client.send
	if &plain.data[0] != &second.data[0] || &second.data[0] != &shared.data[0] {
		t.Fatal("peers did not share immutable JSON before per-socket compression")
	}
	var packet stateWire
	if err := json.Unmarshal(world, &packet); err != nil || packet.World == nil || packet.Generation != g.Generation {
		t.Fatalf("reliable world packet was not plain JSON: %v", err)
	}
	// Direct replaceable sends use the same lossless transport and can replace
	// an unsent update without requiring the dropped frame as a dictionary.
	h.sendState(players[1].Client, r)
	g.Tick++
	h.sendState(players[1].Client, r)
	latest := <-players[1].Client.updates
	want, _ := encodePacket(h.stateWire(r))
	if !bytes.Equal(latest.data, want) {
		t.Fatal("coalescing did not retain the newest complete JSON snapshot")
	}
}

const lenLimitForTest = 128 << 10

func machineGunWireLoad(t testing.TB) [][]byte {
	t.Helper()
	g := newGame(42)
	g.Rules.MapSize = "ultrawide"
	g.startMatch(testPlayers(maxTanks))
	g.Phase = "playing"
	for _, tank := range g.Tanks {
		tank.Invulnerable = 100
		tank.SpawnProtected = false
		g.grantPower(tank, "rapid")
	}
	h := newHub(1)
	r := &Room{Game: g}
	var packets [][]byte
	for i := 0; i < 240; i++ {
		g.Tick++
		for _, tank := range g.Tanks {
			if tank.MachineRounds == 0 {
				g.grantPower(tank, "rapid")
			}
			if !g.fire(tank) {
				t.Fatal("machine gun stream stalled")
			}
		}
		g.updateBullets(tickDT)
		if g.Tick%2 == 0 {
			data, ok := encodePacket(h.stateWire(r))
			if !ok {
				t.Fatal("snapshot encoding failed")
			}
			packets = append(packets, data)
		}
	}
	return packets
}

func TestSnapshotDeflateUnderMachineGunLoad(t *testing.T) {
	packets := machineGunWireLoad(t)
	c, _, reader := transportPair(t, true)
	written := make(chan error, 1)
	go func() {
		for _, packet := range packets {
			if err := c.writeText(packet); err != nil {
				written <- err
				return
			}
		}
		written <- nil
	}()
	var rawSecond, compressedSecond, rawPeak, compressedPeak int
	for i, data := range packets {
		encoded, compressed, err := readTransportMessage(reader)
		if err != nil {
			t.Fatal(err)
		}
		decoded, err := inflateMessage(encoded, lenLimitForTest)
		if !compressed || err != nil || !bytes.Equal(decoded, data) {
			t.Fatalf("snapshot %d did not round-trip: %v", i, err)
		}
		rawPeak, compressedPeak = max(rawPeak, len(data)), max(compressedPeak, len(encoded))
		if i >= len(packets)-30 {
			rawSecond += len(data)
			compressedSecond += len(encoded)
		}
	}
	if err := <-written; err != nil {
		t.Fatal(err)
	}
	if compressedSecond > rawSecond/3 {
		t.Fatalf("expected at least 2/3 bandwidth saved, got %d vs %d bytes in last second", compressedSecond, rawSecond)
	}
	t.Logf("last-second payload %d → %d B/client, peak %d → %d B/frame", rawSecond, compressedSecond, rawPeak, compressedPeak)
}

func BenchmarkSnapshotDeflateMachineGunLoad(b *testing.B) {
	packets := machineGunWireLoad(b)
	packets = packets[len(packets)-30:]
	benchmarkSocketCompression(b, packets)
}

// Measure the library's real compressed socket writes rather than an obsolete
// shared compressor. JSON is already encoded, matching the production queue.
func benchmarkSocketCompression(b *testing.B, packets [][]byte) {
	c, peer, reader := transportPair(b, true)
	_ = peer.SetDeadline(time.Time{})
	type drained struct{ messages, bytes int }
	read := make(chan drained, 1)
	go func() {
		var total drained
		for {
			packet, _, err := readTransportMessage(reader)
			if err != nil {
				read <- total
				return
			}
			total.messages++
			total.bytes += len(packet)
		}
	}()
	b.SetBytes(int64(len(packets[len(packets)-1])))
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if err := c.writeText(packets[i%len(packets)]); err != nil {
			b.Fatal(err)
		}
	}
	b.StopTimer()
	c.close()
	total := <-read
	if total.messages != b.N {
		b.Fatalf("reader received %d of %d snapshots", total.messages, b.N)
	}
	b.ReportMetric(float64(total.bytes)/float64(total.messages), "wire-bytes")
}
