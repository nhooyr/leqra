# leqra v4.40.0 verification

## Executed checks

- Full `go test -race -count=1 -json ./...`: **600 top-level tests; 1,230 including subtests**, all passed.
- Full `node --test --test-reporter=tap tests/*.test.cjs`: **427 passed; 0 failed**.
- `go vet ./...` and the production `go build -trimpath`: passed with Go 1.23.12. The final build includes the audio changes.
- Five shipped JavaScript files passed syntax checks; all 69 retained Python files parsed.
- Eleven HTML asset references resolve; six root JavaScript/CSS/SVG files match their versioned production copies exactly.
- Server, browser, HTML, PWA registration and offline cache use 4.40.0; only the current asset directory is shipped.
- The removed volume explanation is absent from root and served JavaScript. Mobile selection/gesture CSS covers all body descendants and retains `touch-action:none` for gameplay controls. `git diff --check` passed.

Raw combined logs are under `tests/results/v4.40.0/`.

## Mobile interaction

Twelve focused tests execute the actual touch-policy functions and joystick/Fire handlers. They cover local and online countdowns, play, round holds, pauses, disconnection and real reconnect transitions. Native selection, context-menu and double-click events are canceled on mobile during a match, including the ammo/status areas and dialogs. Ordinary clicks, single-finger scrolling and separate joystick/Fire pointers remain intact.

Selection tests cover clearing a selection carried from the lobby, collapsing selected input text without changing its value, preserving a typing caret, avoiding repeated selection-change writes and suspending cleanup during IME composition. Desktop text selection remains available. The existing keyboard/focus handlers and styles are retained.

Actual queued local and online final previews now retain the lock until their two-second hold expires and the final overlay appears. Invalidated previews release immediately. Listener-count tests verify one registration per active period and full cleanup in lobby/results, including abandoned reconnects.

Implementation references: WebKit documents [double-tap suppression with touch-action: manipulation](https://webkit.org/blog/5610/more-responsive-tapping-on-ios/); MDN describes [scroll-container touch-action behavior](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action), [user-select](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/user-select), [selectstart cancellation](https://developer.mozilla.org/en-US/docs/Web/API/Node/selectstart_event) and [Safari touch callouts](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/-webkit-touch-callout). The double-click listener is secondary protection; native Safari double-tap handling is not assumed to always dispatch that DOM event.

## Tank badges

Two positional regressions failed before the change. Seventeen focused badge/render/protection checks passed afterward. The tests cover one to five icons, local bots and remote human tanks, 25 center/edge/corner positions, three render scales, tank rotation, shield charge/timer changes and expiry/reacquisition. Equal loadouts retain equal offsets from the tank. Label positions, close spacing and clockwise order remain unchanged. Boundary clipping is intentional under the requested fixed-position behavior.

## Audio gain and quality safeguards

Nineteen focused audio tests passed, including the retained unlock, resume, scrolling, cancellation and mute checks. Slider values 0/25/50/75/100 produce requested master gains 0/1/2/3/4. Default 50%, saved percentages, midpoint snapping, mute and the existing 12 ms volume ramp are preserved.

The shared Web Audio graph contains one peak compressor and one compensation gain per context. Tests verify routing, parameter settings, node reuse, unmodified per-effect envelopes and compensation for automatic makeup gain. Parameters are threshold −3 dB, knee 0, ratio 20, attack 0 and release 80 ms. The configured steady-state transfer calculation remains below 0.82 for an input amplitude of 10.4, a conservative sum of eight explosions plus shots. This is a transfer calculation and graph test, not a measurement of a browser's compressor transients.

Makeup compensation follows the [Web Audio specification](https://www.w3.org/TR/webaudio-1.1/#computing-the-makeup-gain), allowing quiet effects to retain their requested gain while loud overlaps compress.

The native fallback scales the entire waveform. Nominal gain remains linear through 0.70, then approaches 0.98 smoothly without a hard plateau. Generated waveforms retain their shape, pitch and silent endpoints. Cache precision was increased so 99% to 100% remains distinguishable even for the loud explosion.

Measured production-encoder explosion samples:

| Slider | Whole-wave gain | Peak absolute PCM sample |
| --- | ---: | ---: |
| 50% | 0.91778 | 28,582 |
| 75% | 0.94267 | 29,358 |
| 99% | 0.95303 | 29,680 |
| 100% | 0.95333 | 29,690 |

At 100%, this generated explosion reaches about 90.61% of 16-bit full scale. Uncompressed ordinary fallback tones retain the requested doubling within PCM rounding. Louder fallback effects receive a smaller boost to preserve headroom. These checks concern generated files and graph setup; native media-element mixing and actual speaker output are not measured.

## Verification limits

No current live-browser or physical-device check was performed; workspace browser previews were previously blocked by security policy. Native Safari selection/callouts and double-tap behavior, clipped badge appearance, compressor transients, mixing and listening quality still need a device retest. No claim of exactly doubled perceived loudness or universally clipping-free hardware output is made. Historical browser scripts and screenshots are not current-release verification.
