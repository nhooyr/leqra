package main

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestInfinityStatusShowsPublicPopulationWithoutJoining(t *testing.T) {
	app := newApp(4, nil)
	now := time.Now()
	pilot := app.infinite.public.join(fakeClient(), "PUBLIC", now)
	pilot.Score = 7
	private := newSeededInfiniteArena(42)
	private.join(fakeClient(), "PRIVATE", now).Score = 100
	app.infinite.private[infiniteRoom{&Room{}, 1}] = private
	commitPublicFixture(t, app.infinite)
	response := httptest.NewRecorder()
	app.handler().ServeHTTP(response, httptest.NewRequest("GET", "/api/infinity", nil))
	if response.Code != 200 || response.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("unexpected status response: %d %v", response.Code, response.Header())
	}
	var status struct {
		Players, TankCount, Capacity int
		Leaders                      []infiniteStatusLeader
	}
	if err := json.Unmarshal(response.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status.Players != 1 || status.TankCount != 1 || status.Capacity != infiniteCapacity || len(status.Leaders) != 1 || status.Leaders[0].Name != "PUBLIC" || status.Leaders[0].Score != 7 || status.Leaders[0].Rank != 1 {
		t.Fatalf("public preview leaked or changed population: %+v", status)
	}
	if len(app.infinite.connections) != 0 || app.infinite.public.players != 1 || strings.Contains(response.Body.String(), "PRIVATE") {
		t.Fatal("preview allocated a connection/tank or exposed a private arena")
	}
}

func TestInfinityStatusCapsRankedStandingsAndRejectsMutation(t *testing.T) {
	app := newApp(4, nil)
	for i := range 14 {
		pilot := app.infinite.public.addPilot("BOT", true, 0, 0, 1, 3)
		pilot.Score = i
	}
	commitPublicFixture(t, app.infinite)
	response := httptest.NewRecorder()
	app.infinityStatus(response, httptest.NewRequest("GET", "/api/infinity", nil))
	var status struct{ Leaders []infiniteStatusLeader }
	if err := json.Unmarshal(response.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if len(status.Leaders) != 10 || status.Leaders[0].Score != 13 || status.Leaders[9].Rank != 10 || status.Leaders[9].Score != 4 {
		t.Fatalf("preview standings were not the ranked top ten: %+v", status)
	}
	response = httptest.NewRecorder()
	app.infinityStatus(response, httptest.NewRequest("POST", "/api/infinity", nil))
	if response.Code != 405 || response.Header().Get("Allow") != "GET" || len(app.infinite.public.pilots) != 14 {
		t.Fatal("preview endpoint accepted a mutation")
	}
}
