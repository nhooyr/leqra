# leqra v4.16 test notes

## Rebrand checks

Focused browser checks verify the visible wordmark is exactly lowercase `leqra`, the page title/meta description use leqra, the Controls footer reports `leqra v4.16.0`, and the canonical public browser object is `window.leqra`.

A migration check seeds representative legacy browser keys and verifies v4.16 copies them into the new `leqra.*` namespace before loading settings. New writes are made to the leqra namespace.

## Regression checks

The v4.15 desktop/mobile focused browser checks were updated to exercise the renamed public API and storage namespace while retaining their gameplay assertions for Ultra Wide, maze stability, per-pilot feedback, FFA roster controls, focus behavior, spectator copy, and result colors.

Final validation includes the complete non-race Go suite (**459 top-level tests / 862 passing test-and-subtest events, 2 opt-in skips, 0 failures**), a targeted race-detector run over version/WebSocket transport paths, **56/56 Node tests**, Go vet, JavaScript syntax checks, and a compiled build named `leqra`. The complete race-instrumented suite exceeded the execution window in this environment, so it is not claimed as a completed v4.16 run.
