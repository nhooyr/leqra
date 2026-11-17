package main

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
	"unicode"
)

type clientCallsignFold struct {
	Ranges  [][4]int    `json:"ranges"`
	Singles [][2]int    `json:"singles"`
	Cases   [][2]string `json:"cases"`
}

func (f clientCallsignFold) scalar(r rune) rune {
	for _, pair := range f.Singles {
		if int(r) == pair[0] {
			return rune(pair[1])
		}
	}
	for _, span := range f.Ranges {
		if int(r) >= span[0] && int(r) <= span[1] && (int(r)-span[0])%span[2] == 0 {
			return r + rune(span[3])
		}
	}
	return r
}

func TestClientCallsignFoldMatchesServerScalars(t *testing.T) {
	data, err := os.ReadFile("tests/fixtures/callsign-fold.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture clientCallsignFold
	if err = json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	for r := rune(0); r <= unicode.MaxRune; r++ {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			continue
		}
		if got, want := string(fixture.scalar(r)), canonicalCallsign(string(r)); got != want {
			t.Fatalf("U+%04X client=%q server=%q", r, got, want)
		}
	}
	for _, pair := range fixture.Cases {
		var folded strings.Builder
		for _, r := range pair[0] {
			folded.WriteRune(fixture.scalar(r))
		}
		if got := folded.String(); got != pair[1] || canonicalCallsign(pair[0]) != pair[1] {
			t.Fatalf("%q client=%q server=%q want=%q", pair[0], got, canonicalCallsign(pair[0]), pair[1])
		}
	}
}

func TestCallsignCleanupKeepsDecimalNumbers(t *testing.T) {
	if got := cleanCallsign("A²Ⅳ٣४𝟡"); got != "A٣४𝟡" {
		t.Fatal("non-decimal numeric characters entered the callsign", got)
	}
}
