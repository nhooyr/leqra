package main

import (
	"fmt"
	"strconv"
	"testing"
	"time"
)

func fullConnectionBudget(now time.Time) *App {
	a := newApp(1, nil)
	for i := 0; i < budgetCapacity; i++ {
		a.ips[strconv.Itoa(i)] = &ipBudget{window: now}
	}
	return a
}

func TestConnectionBudgetCapacityAndExpiry(t *testing.T) {
	now := time.Now()
	a := fullConnectionBudget(now)
	if a.reserve("new", now) || len(a.ips) != budgetCapacity {
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

func TestIPv6PrivacyAddressesShareConnectionBudget(t *testing.T) {
	a, now := newApp(1, nil), time.Now()
	for i := 1; i <= budgetCapacity; i++ {
		source := connectionSource(fmt.Sprintf("[2001:db8:100:200::%x]:9876", i))
		if admitted := a.reserve(source, now); admitted != (i <= 120) {
			t.Fatalf("attempt %d from %s: admission = %t", i, source, admitted)
		} else if admitted {
			a.release(source)
		}
	}
	if len(a.ips) != 1 || !a.reserve(connectionSource("[2001:db8:100:201::1]:9876"), now) {
		t.Fatal("IPv6 aliases filled the table or blocked another network")
	}
	if got := connectionSource("[::ffff:192.0.2.1]:9876"); got != connectionSource("192.0.2.1:1234") {
		t.Fatalf("IPv4-mapped address has a separate budget: %s", got)
	}
	if got := connectionSource("[fe80::a%en0]:9876"); got != "fe80::/64" {
		t.Fatalf("IPv6 scope prevented prefix normalization: %s", got)
	}
}

func TestConnectionBudgetBoundsExpirySweeps(t *testing.T) {
	now := time.Now()
	a := fullConnectionBudget(now.Add(-budgetWindow + time.Millisecond))
	if a.reserve("new", now) {
		t.Fatal("full table admitted another budget before expiry")
	}
	if a.reserve("new", now.Add(time.Millisecond)) || !a.nextBudgetSweep.Equal(now.Add(time.Second)) {
		t.Fatal("request burst caused another expiry scan")
	}
	if !a.reserve("new", now.Add(time.Second)) {
		t.Fatal("next expiry scan did not reclaim stale budgets")
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
