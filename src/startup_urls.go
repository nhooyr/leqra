package main

import (
	"context"
	"net"
	"net/url"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"
)

func startupURLs(bound *net.TCPAddr, addrs []net.Addr, findHostname func([]net.IP) string) (string, []string) {
	port := strconv.Itoa(bound.Port)
	httpURL := func(host string) string {
		return (&url.URL{Scheme: "http", Host: net.JoinHostPort(host, port)}).String()
	}
	open := httpURL("localhost")
	if !bound.IP.IsUnspecified() && !bound.IP.Equal(net.IPv4(127, 0, 0, 1)) && !bound.IP.Equal(net.IPv6loopback) {
		host := bound.IP.String()
		if bound.Zone != "" {
			host += "%" + bound.Zone
		}
		open = httpURL(host)
	}
	if bound.IP.IsLoopback() {
		return open, nil
	}

	if !bound.IP.IsUnspecified() {
		if host := findHostname([]net.IP{bound.IP}); host != "" {
			return open, []string{httpURL(host)}
		}
		return open, nil
	}

	var ips []net.IP
	var ipv4, ipv6 []string
	for _, addr := range addrs {
		if network, ok := addr.(*net.IPNet); ok && network.IP.IsGlobalUnicast() {
			ip := network.IP
			if ip.To4() != nil {
				ipv4 = append(ipv4, httpURL(ip.String()))
			} else if bound.IP.To4() == nil {
				ipv6 = append(ipv6, httpURL(ip.String()))
			} else {
				continue
			}
			ips = append(ips, ip)
		}
	}
	if len(ips) > 0 {
		if host := findHostname(ips); host != "" {
			return open, []string{httpURL(host)}
		}
	}
	if len(ipv4) > 0 {
		return open, ipv4
	}
	return open, ipv6
}

func lanHostname(ips []net.IP) string {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	hostname, _ := os.Hostname()
	candidates := []string{hostname}
	if runtime.GOOS == "darwin" {
		// The system hostname can come from DHCP. Bonjour uses LocalHostName.
		if name, err := exec.CommandContext(ctx, "/usr/sbin/scutil", "--get", "LocalHostName").Output(); err == nil {
			if local := strings.TrimSpace(string(name)); local != "" && !strings.EqualFold(local+".local", hostname) {
				candidates = append([]string{local + ".local"}, candidates...)
			}
		}
	}
	for _, host := range candidates {
		if host == "" {
			continue
		}
		resolved, _ := net.DefaultResolver.LookupIPAddr(ctx, host)
		for _, address := range resolved {
			for _, ip := range ips {
				if ip.Equal(address.IP) {
					return host
				}
			}
		}
	}
	return ""
}
