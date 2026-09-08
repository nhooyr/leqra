# leqra v4.19 — Safari smoothness and mobile stability

## What changed

v4.19 is a WebKit-focused performance and reliability pass. Game rules, physics, collision, scoring, matchmaking authority, pickup behavior, and the v4.18 results/rematch flow are unchanged.

### Safari / WebKit rendering

Safari and all iOS WebKit browsers now use a deliberately lighter renderer:

- adaptive arena Canvas density is capped at **1.75× on desktop WebKit** and **1.5× on touch WebKit**, with total backing-pixel budgets as an additional guard;
- the static maze cache is capped at **3.0 million pixels on desktop WebKit** and **2.0 million on touch WebKit**, instead of the normal 5.0-million-pixel budget;
- full-screen/modal backdrop blur and dynamic Canvas glow blur are disabled on WebKit;
- WebKit uses a lower cosmetic particle ceiling and 80% of the ordinary burst count;
- remote projectile trails retain 7 samples on WebKit instead of 11;
- power-up legend canvases cap at 2× backing resolution on WebKit.

These changes affect cosmetic rendering only. Chromium retains the existing higher-quality budgets.

### iPhone / iPad input and layout fixes

- iPadOS is recognized as touch-capable even when Safari reports `MacIntel`/desktop-style pointer behavior, so a connected trackpad cannot make the touch HUD disappear.
- Joystick geometry is cached on pointer-down. Pointer-move no longer calls `getBoundingClientRect()` every event.
- `setPointerCapture()` is guarded and window-level `pointerup` / `pointercancel` fallbacks clear both joystick and FIRE state if WebKit loses capture during multi-touch.
- Safari gesture events are suppressed over the Canvas/touch controls to stop accidental pinch zoom while steering and firing.
- Editable controls on iOS stay at **16px** on small screens so Safari does not auto-zoom the page when a room/rules/chat field receives focus.
- touch landscape uses `visualViewport.height` when available, and iOS uses a stable small-viewport app height.
- Visual Viewport and ResizeObserver changes are coalesced through animation frames; a one-pixel fractional WebKit size wobble no longer reallocates the full Canvas.
- rotation and back/forward-cache restores clear stale held input and re-measure the arena/frame clock.

### First-touch audio latency

Creating/resuming the AudioContext no longer generates the explosion-noise sample immediately. The noise buffer is generated lazily on the first explosion, removing that CPU work from the first control/audio gesture.

## Compatibility

Existing `leqra.*` settings, controls, presets, rooms, protocol behavior, and v4.18 browser-storage state remain compatible. No database or npm step was added.

The desktop non-Chromium notice remains: Safari is supported and has been optimized, while Chrome is still recommended for the smoothest desktop experience.

## Install

Replace all Go source files and the complete `web/` directory, then rebuild/restart the server:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

For development:

```sh
go run .
```

Refresh connected browsers after deployment because the browser assets are embedded in the Go executable. `/healthz`, `/api/config`, the Controls footer, and `window.leqra.version` report **4.19.0**.

## Testing note

This environment does not contain a native Safari/WebKit automation runtime and could not download Playwright WebKit. The dedicated Safari suite therefore executes Safari/iPhone/iPad code paths under Chromium identities. See **TEST-NOTES-v4.19.md** for exactly what was verified and what still requires physical Safari acceptance testing.
