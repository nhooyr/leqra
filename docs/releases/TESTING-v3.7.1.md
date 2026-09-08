# leqra v3.7.1 — flag-caption patch verification

This release removes only the Canvas flag/base captions and their caption
backing strips. The backend version identifier changes, but no Go gameplay or
networking logic changes. `web/netcode.js` and all other browser assets besides
`web/game.js` are unchanged from v3.7.0.

## Executed checks

- **345 top-level Go tests passed with the race detector** (653 including subtests).
- **24 JavaScript networking tests passed.**
- **85 focused browser assertions passed** across four desktop/phone viewports.
- `go vet`, both JavaScript syntax checks, and a compiled server build passed.

The rendering test uses the actual game scripts and Canvas drawing calls. For
home, dropped and carried flags, it verifies that only the team numbers appear
on pennants, no caption backing is drawn, and the full arena render has no
flag/base captions. It also checks the objective HUD, immutable objective data,
arena geometry, page bounds and pixel-level tank-over-flag layering. Desktop
home-state and compact-phone carried-state screenshots were visually inspected.

```sh
go test -race -count=1 ./...
go vet ./...
node --check web/game.js
node --check web/netcode.js
node --test tests/netcode.test.cjs
go build -trimpath -o leqra .
python tests/flag_labels_browser.py --browser /usr/bin/chromium \
  --output test-output/flag-labels
```

Python Playwright and Chromium are needed only for the optional browser test,
not to run the game. New machine-readable results are stored under
`tests/results/*v3.7.1*`. Earlier reports are historical runs, not additional
current executions. `TESTING-v3.7.md` preserves the previous release's verification.

## Limits

The new browser suite uses Chromium desktop/mobile emulation with exact shipped
assets injected into pages and synthetic Location/storage adapters. It does not
run an online match, test physical devices, Safari/Firefox, public deployment,
actual address-bar navigation, or remeasure network smoothing/performance.
Online and spectator flag rendering use the same unchanged data path and shared
`drawFlags` renderer. The server build is checked separately. No gameplay or
post-match statistics logic is altered by this patch.
