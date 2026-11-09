package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func TestTouchSteeringParity(t *testing.T) {
	data, err := os.ReadFile("tests/fixtures/touch-steering.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []struct {
		Name       string
		Angle      float64
		Input      Input
		TurnScale  float64
		AngleAfter float64
		Throttle   float64
	}
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	for _, tc := range cases {
		t.Run(tc.Name, func(t *testing.T) {
			angle, throttle := steerTank(tc.Angle, tc.Input, tc.TurnScale, tickDT)
			if math.Abs(delta(angle, tc.AngleAfter)) > 1e-12 || math.Abs(throttle-tc.Throttle) > 1e-12 {
				t.Fatalf("angle %.15g, throttle %.15g; want %.15g, %.15g", angle, throttle, tc.AngleAfter, tc.Throttle)
			}
		})
	}
}
