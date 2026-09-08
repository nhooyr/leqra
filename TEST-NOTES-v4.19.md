# leqra v4.19 test notes

## Final automated verification

The final source tree passed:

- `go test -race -count=1 -json ./...` — **463 top-level tests passed**, **866 passing test/subtest events**, **0 failures**, **2 opt-in skips**;
- `node --test tests/*.test.cjs` — **56/56 passed**;
- `go vet ./...` — passed;
- `node --check web/theme.js` — passed;
- `node --check web/netcode.js` — passed;
- `node --check web/game.js` — passed;
- `go build -trimpath` — passed.
- live compiled-server smoke — `/healthz` and `/api/config` reported **4.19.0**, the served title was **leqra — Tank Arena**, and the startup banner was `leqra online v4.19.0`.
- `go test -shuffle=on -count=1 ./...` — passed.

The two Go skips are the existing opt-in browser/movement fixture harnesses, not failures.

## Safari / WebKit focused regression

`tests/safari419_browser.py` passed **23/23** checks. It covers the shipped Safari/WebKit branches for:

- desktop Safari identification and the existing Chrome recommendation;
- desktop WebKit Canvas density capped at 1.75×;
- WebKit backdrop blur removal;
- one-pixel fractional ResizeObserver jitter not reallocating the Canvas;
- iPhone/iOS WebKit identification and touch-control activation;
- touch WebKit Canvas density capped at 1.5×;
- no portrait horizontal document overflow;
- iOS editable controls remaining at 16px to avoid focus auto-zoom;
- power-up legend backing resolution capped at 2×;
- one joystick geometry/layout read per touch gesture rather than one per pointer-move;
- simulated WebKit pointer-capture failure/cancellation not leaving joystick or FIRE held;
- gesture zoom being prevented over game controls;
- iPhone landscape selecting the compact touch layout with arena/touch HUD inside the viewport;
- Macintosh-style iPadOS Safari still being recognized as iOS/touch capable;
- no uncaught JavaScript errors in those paths.

### Important native-Safari limit

The build environment has system Chromium but no installed Playwright WebKit/Safari engine. An attempt to install Playwright WebKit could not reach the package host from this environment. The Safari regression therefore uses Chromium as a DOM/JavaScript host with Safari/iPhone/iPad identities. It validates the actual shipped engine-detection, CSS, pointer fallback, sizing, and mobile-layout branches; it **does not measure native Safari FPS/GPU behavior**. Physical Safari on macOS and iPhone/iPad should still be used for final real-device acceptance.

## Retained browser regressions

The previous release checks were rerun against v4.19:

- branding/storage migration: **12/12**;
- desktop gameplay/HUD: **16/16**;
- narrow mobile gameplay/layout: **6/6**;
- v4.18 results/layout/browser behavior: **9/9**.

All passed with no uncaught browser errors.

## Real WebSocket matchmaking

The production-style Go WebSocket browser harness passed **71/71** checks, including queue formation, party consent, local P2, chat, transfer into battle, reconnects, spectator behavior, queued rematch voting, results copy, and BACK TO ROOM restoring the reserved private party.

## Performance-oriented changes verified by code-path assertions

Relative to v4.18's ordinary 2× arena Canvas cap, the WebKit touch cap of 1.5× reduces backing pixels by **43.75%** for the same CSS arena dimensions before the additional total-pixel guard is considered. The desktop WebKit 1.75× cap uses **23.4% fewer backing pixels** than 2× at the same CSS dimensions. Static maze-cache caps are reduced from 5.0M pixels to 3.0M desktop / 2.0M touch on WebKit.

These are backing-store workload reductions, not claimed FPS gains. The suite also directly verifies that joystick pointer-move no longer performs repeated layout reads.

Retained server benchmarks still report **0 allocs/op** for the eight-hard-bot Huge-map benchmark and **2 allocs/op** for room broadcasting; no server hot-path regression was introduced by this browser-focused release.
