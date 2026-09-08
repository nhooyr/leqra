# leqra v4.22 test notes

## Verification performed

- Full race-enabled Go suite passed: **474** top-level tests, **877** passing test/subtest events, **0 failures**, and **2** intentionally opt-in fixture skips.
- `go vet ./...` passed.
- `go build -trimpath` passed.
- **57/57** JavaScript/Node tests passed, including Ghost reconciliation coverage.
- **26/26** Safari/WebKit identity checks passed. They cover the desktop Safari Chrome/Firefox recommendation, no desktop notice on iPhone Safari, native-audio fallback with Web Audio unavailable, iPhone touch unlock, iPadOS desktop-style identity handling, WebKit render budgets, and mobile input/layout safeguards.
- **7/7** delayed-Web-Audio/volume checks passed.
- **9/9** focused v4.22 browser checks passed: buttonless callsign auto-save, Join-only room navigation, buttonless room-code auto-save, dropdown chevron spacing, one integrated chat button, the compact opponent-send switch, Ghost wall separation, and no uncaught errors.
- **8/8** retained v4.18 presentation checks passed, including the restored desktop-Safari Chrome/Firefox recommendation.
- **87/87** real-WebSocket matchmaking browser checks passed. The live run verifies one integrated transcript, party-only and opponent-only delivery/non-leakage, the compact outgoing target switch, opponent unread/notification behavior, 320px layout, P1/P2 input, spectators, reconnects, results/rematch, return-to-room, and no uncaught browser errors.
- **128/128** production matchmaking protocol checks passed.
- The served CSP is covered by a Go regression requiring `media-src 'self' blob:` so Safari's generated WAV fallback cannot silently be blocked by leqra's own security policy again.
- Representative hot-path benchmarks remain at the optimized floor: eight hard bots report **0 allocations/op** (about 38–44 µs/op in this container), and room broadcasting remains **2 allocations/op / ~5.35 KB/op** (about 22–27 µs/op).

## Bugs fixed during the audit

1. **Safari fallback blocked by CSP:** the v4.21 native Safari fallback generated WAV `blob:` URLs, but the served Content-Security-Policy did not allow `blob:` media. v4.22 explicitly allows `media-src 'self' blob:` and strengthens trusted-gesture activation for both native Audio and Web Audio.
2. **Repeated Safari unlock work:** WebKit compatibility priming was repeated on every click/touch even after successful activation. Priming is now idempotent and retries only when audio still needs unlocking.
3. **Ghost cross-wall tank pull:** a ghosted tank could overlap another tank on the opposite side of an interior wall, allowing ordinary tank-separation physics to push it sideways across the wall. The authoritative Go and local browser simulations now ignore only that cross-wall overlap force while Ghost is active. Ghost reconciliation also clears stale positional smoothing while phasing.
4. **Integrated-chat switch hit target:** the first compact toggle styling made the invisible checkbox ignore pointer events, so direct automated/assistive interaction could be intercepted by its label text. The checkbox now covers the full switch as the actual hit target while retaining keyboard focus styling.
5. **Duplicate Unshare teardown for local P2:** P1 and local P2 may share one WebSocket. Unshare sends one teardown packet per connection and uses a bounded fixed scratch array rather than allocating a temporary map.
6. **Half-wired room editing controls:** the partially updated v4.22 source had removed some buttons before all no-op/blur/Enter flows were finished. Callsign and room-code edits now normalize before comparing, avoid needless network writes, and save on blur or Enter without separate Save/Rename buttons.

## Safari test limitation

Native Safari/WebKit is not installed in this build container. The Safari suite runs the shipped WebKit/iOS detection, CSS, touch, sizing and fallback code under Safari identities in system Chromium. The audio test deliberately removes usable Web Audio so Safari's native Audio fallback is exercised, and the server regression independently checks the real CSP requirement for the generated `blob:` WAV media. This is substantially closer to the real failure than the v4.21 emulation, but a physical Mac/iPhone/iPad remains the final listening/performance acceptance target.
