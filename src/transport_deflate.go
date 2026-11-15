package main

import (
	"strconv"
	"strings"
)

// Use the RFC 7692 extension without a shared dictionary in either direction.
// An unsupported offer falls back to ordinary JSON text frames.
func acceptsSnapshotDeflate(values []string) bool {
	for _, value := range values {
		for _, offer := range strings.Split(value, ",") {
			parts := strings.Split(offer, ";")
			if strings.TrimSpace(parts[0]) == "permessage-deflate" && validDeflateOffer(parts[1:]) {
				return true
			}
		}
	}
	return false
}

func validDeflateOffer(params []string) bool {
	seen := make(map[string]bool, len(params))
	for _, param := range params {
		name, value, assigned := strings.Cut(param, "=")
		name = strings.TrimSpace(name)
		if seen[name] {
			return false
		}
		seen[name] = true
		switch name {
		case "server_no_context_takeover", "client_no_context_takeover":
			if assigned {
				return false
			}
		case "client_max_window_bits":
			// The offer is a hint, so the reply need not include this parameter.
			if assigned {
				value = strings.TrimSpace(value)
				if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
					value = value[1 : len(value)-1]
				}
				bits, err := strconv.Atoi(value)
				if err != nil || bits < 8 || bits > 15 || strconv.Itoa(bits) != value {
					return false
				}
			}
		default:
			// The standard flate writer cannot guarantee a smaller server window.
			return false
		}
	}
	return true
}

type snapshotFrame struct {
	data []byte
}
