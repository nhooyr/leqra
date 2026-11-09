package main

import (
	"net"
	"slices"
	"testing"
)

func TestStartupURLs(t *testing.T) {
	lanIP := net.ParseIP("192.0.2.14")
	v6IP := net.ParseIP("2001:db8::14")
	ifaces := []net.Addr{
		&net.IPNet{IP: net.IPv4(127, 0, 0, 1)},
		&net.IPNet{IP: lanIP},
		&net.IPNet{IP: v6IP},
	}
	for _, tc := range []struct {
		name       string
		bound      net.TCPAddr
		hostname   string
		wantOpen   string
		wantLAN    []string
		resolveIPs []net.IP
	}{
		{"hostname", net.TCPAddr{IP: net.IPv6zero, Port: 45678}, "host.local", "http://localhost:45678", []string{"http://host.local:45678"}, []net.IP{lanIP, v6IP}},
		{"IP fallback", net.TCPAddr{IP: net.IPv4zero, Port: 45678}, "", "http://localhost:45678", []string{"http://192.0.2.14:45678"}, []net.IP{lanIP}},
		{"loopback only", net.TCPAddr{IP: net.IPv6loopback, Port: 45678}, "host.local", "http://localhost:45678", nil, nil},
		{"bound interface", net.TCPAddr{IP: lanIP, Port: 45678}, "host.local", "http://192.0.2.14:45678", []string{"http://host.local:45678"}, []net.IP{lanIP}},
		{"bound IPv6 fallback", net.TCPAddr{IP: v6IP, Port: 45678}, "", "http://[2001:db8::14]:45678", nil, []net.IP{v6IP}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var resolved bool
			open, lan := startupURLs(&tc.bound, ifaces, func(ips []net.IP) string {
				resolved = true
				if !slices.EqualFunc(ips, tc.resolveIPs, net.IP.Equal) {
					t.Fatalf("hostname lookup got addresses %v, want %v", ips, tc.resolveIPs)
				}
				return tc.hostname
			})
			if resolved != (len(tc.resolveIPs) > 0) {
				t.Fatalf("hostname looked up: %t", resolved)
			}
			if open != tc.wantOpen || !slices.Equal(lan, tc.wantLAN) {
				t.Errorf("Open %q, LAN %v; want Open %q, LAN %v", open, lan, tc.wantOpen, tc.wantLAN)
			}
		})
	}
}
