package main

import (
	"bytes"
	"errors"
	"testing"
	"time"
)

func TestWebSocketTransportMessageAndControlRateBounds(t *testing.T) {
	for _, opcode := range []byte{9, 10} {
		frames := bytes.Repeat(maskedFrame(opcode, true, nil), maxTransportMessagesPerSecond+1)
		frames = append(frames, maskedFrame(1, true, []byte("end"))...)
		_, err := parseFrames(t, frames)
		var policy *wsError
		if !errors.As(err, &policy) || policy.code != 1008 {
			t.Fatal("control flood did not close with a policy violation", opcode, err)
		}
	}
	c := &wsConn{messageWindow: time.Now()}
	for range maxTransportMessagesPerSecond {
		if !c.countMessage() {
			t.Fatal("valid message/control budget was cut short")
		}
	}
	if c.countMessage() {
		t.Fatal("completed messages bypassed the shared control budget")
	}
	c.messageWindow = time.Now().Add(-time.Second)
	if !c.countMessage() || c.messages != 1 {
		t.Fatal("transport budget did not renew")
	}
}

func TestWebSocketByteBudgetRefillsWithinItsBoundedBurst(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	c := &socketByteBudget{at: now, available: wsInboundByteBurst}
	if c.allowance(now) != wsInboundByteBurst {
		t.Fatal("initial wire burst changed")
	}
	c.available = 0
	if c.allowance(now.Add(500*time.Millisecond)) != wsInboundBytesPerSecond/2 {
		t.Fatal("wire budget did not refill at its sustained rate")
	}
	if c.allowance(now.Add(time.Hour)) != wsInboundByteBurst {
		t.Fatal("idle sockets accumulated an unbounded burst")
	}
}

func TestWebSocketByteBudgetStopsEmptyContinuationFloods(t *testing.T) {
	frames := maskedFrame(1, false, nil)
	frames = append(frames, bytes.Repeat(maskedFrame(0, false, nil), wsInboundByteBurst/3)...)
	_, err := parseFrames(t, frames)
	var policy *wsError
	if !errors.As(err, &policy) || policy.code != 1008 {
		t.Fatal("fragment flood bypassed the parser-free inbound byte budget", err)
	}
}

func TestWebSocketIncompleteMessageCannotOutliveItsDeadlineUsingPongs(t *testing.T) {
	c, peer, _ := transportPair(t, false)
	done := make(chan struct{})
	go func() {
		defer close(done)
		if _, err := peer.Write(maskedFrame(1, false, nil)); err != nil {
			return
		}
		for range 100 {
			if _, err := peer.Write(maskedFrame(10, true, []byte("alive"))); err != nil {
				return
			}
			time.Sleep(5 * time.Millisecond)
		}
	}()
	start := time.Now()
	if _, err := c.readMessageWithTimeout(50 * time.Millisecond); err == nil {
		t.Fatal("incomplete message unexpectedly completed")
	}
	if time.Since(start) > time.Second {
		t.Fatal("control traffic extended an incomplete message deadline")
	}
	_ = peer.Close()
	<-done
}
