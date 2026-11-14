package main

import "strings"

type callsignReservedError struct{ Conflicts []callsignConflict }

func (e *callsignReservedError) Error() string {
	return "Callsigns beginning with Bot and a space are reserved for bots. Choose another callsign."
}

func reservedCallsign(name string) bool {
	key := canonicalCallsign(name)
	return key == "bot" || strings.HasPrefix(key, "bot ")
}

func reservedCallsigns(names []string) error {
	var conflicts []callsignConflict
	for seat, name := range names {
		if reservedCallsign(name) {
			conflicts = append(conflicts, callsignConflict{Seat: seat, Name: cleanCallsign(name)})
		}
	}
	if len(conflicts) != 0 {
		return &callsignReservedError{Conflicts: conflicts}
	}
	return nil
}
