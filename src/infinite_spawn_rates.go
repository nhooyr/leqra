package main

import (
	"bytes"
	"encoding/json"
	"errors"
)

type infinityBotSpawnRates map[string]float64

// A null entire field means legacy rules; null inside the map is not a number
// and must not silently switch that tier Off through encoding/json coercion.
func (rates *infinityBotSpawnRates) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	next := make(infinityBotSpawnRates, len(raw))
	for tier, value := range raw {
		if bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return errors.New("Infinity bot spawn rates must be numbers.")
		}
		var rate float64
		if err := json.Unmarshal(value, &rate); err != nil {
			return err
		}
		next[tier] = rate
	}
	*rates = next
	return nil
}

// The master switch is separate: legacy migration retains the selected mix
// even while roaming is disabled. A present empty map means every tier is Off.
func effectiveInfinityBotSpawnRates(r MatchRules) map[string]float64 {
	if r.InfinityBotSpawnRates != nil {
		rates := make(map[string]float64, len(*r.InfinityBotSpawnRates))
		for tier, rate := range *r.InfinityBotSpawnRates {
			rates[tier] = rate
		}
		return rates
	}
	rate := r.InfinityBotSpawnRate
	if rate == 0 {
		rate = 2
	}
	level := infiniteBotLevel(r.InfinityBotDifficulty)
	if !r.InfinityRandomDifficulty {
		return map[string]float64{infiniteBotTunings[level].name: rate}
	}
	rates := make(map[string]float64, level+1)
	for _, tuning := range infiniteBotTunings[:level+1] {
		rates[tuning.name] = rate / float64(level+1)
	}
	return rates
}

func (a *infiniteArena) roomBotSpawnRate() float64 {
	return infinitySpawnRateTotal(a.rules.BotSpawnRates)
}

func infinitySpawnRateTotal(rates map[string]float64) float64 {
	var total float64
	for _, tuning := range infiniteBotTunings {
		total += rates[tuning.name]
	}
	return total
}

// Use canonical tier order, independent of JSON/map iteration order. A fixed
// one-tier mix does not consume an unnecessary random draw.
func (a *infiniteArena) chooseRoomBotLevel() int {
	count, last, total := 0, infiniteNormalBot, 0.0
	for level, tuning := range infiniteBotTunings {
		if rate := a.rules.BotSpawnRates[tuning.name]; rate > 0 {
			count++
			last = level
			total += rate
		}
	}
	if count <= 1 {
		return last
	}
	draw := a.random.Float64() * total
	for level, tuning := range infiniteBotTunings {
		rate := a.rules.BotSpawnRates[tuning.name]
		if draw < rate {
			return level
		}
		draw -= rate
	}
	return last
}
