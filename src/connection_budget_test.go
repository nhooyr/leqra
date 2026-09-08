package main

import (
	"strconv"
	"testing"
	"time"
)

func fullConnectionBudget(now time.Time) *App {
	a := newApp(1, nil)
	for i := 0; i < 8192; i++ {
		a.ips[strconv.Itoa(i)] = &ipBudget{window: now}
	}
	return a
}

func TestConnectionBudgetCapacityAndExpiry(t *testing.T) {
	now := time.Now()
	a := fullConnectionBudget(now)
	if a.reserve("new", now) || len(a.ips) != 8192 {
		t.Fatal("new address exceeded the connection-budget capacity")
	}
	if !a.reserve("0", now) {
		t.Fatal("full table rejected a known address with available budget")
	}
	if !a.reserve("new", now.Add(time.Minute)) {
		t.Fatal("expired inactive budgets prevented admitting a new address")
	}
	if a.ips["0"] == nil || a.ips["0"].active != 1 {
		t.Fatal("expiry cleanup discarded an active connection")
	}
}

func TestConnectionBudgetExpiresAtWindowBoundary(t *testing.T) {
	now := time.Now()
	a := fullConnectionBudget(now)
	if !a.reserve("new", now.Add(time.Minute)) || len(a.ips) != 1 {
		t.Fatal("inactive budgets were not reclaimed at the window boundary")
	}
}

func TestConnectionBudgetKnownAddressKeepsRateLimits(t *testing.T) {
	now := time.Now()
	a := fullConnectionBudget(now)
	for i := 0; i < 120; i++ {
		if !a.reserve("0", now) {
			t.Fatalf("attempt %d rejected before the limit", i+1)
		}
		a.release("0")
	}
	if a.reserve("0", now) {
		t.Fatal("known address bypassed the attempt limit")
	}
	if !a.reserve("0", now.Add(time.Minute)) {
		t.Fatal("attempt budget did not reset at the window boundary")
	}
	a.ips["0"].active = 256
	if a.reserve("0", now.Add(2*time.Minute)) {
		t.Fatal("window reset bypassed the active connection limit")
	}
}

func BenchmarkConnectionBudgetKnownAddress(b *testing.B) {
	now := time.Now()
	a := fullConnectionBudget(now)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		a.ips["0"].attempts = 0
		if !a.reserve("0", now) {
			b.Fatal("reservation rejected")
		}
		a.release("0")
	}
}
