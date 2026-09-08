# leqra v4.8 — focused grenade test notes

## New regressions

- Go verifies the actual grenade retains >87% launch speed after five seconds and
  >74% with two seconds remaining, then enters the intended late braking phase.
- Go verifies the integrated drag result is invariant whether the fuse is advanced in
  one interval or 600 smaller intervals.
- Chromium verifies the same speed checkpoints using the shipped JavaScript and checks
  that the bot grenade forecast advances both velocity and remaining fuse consistently.
- The existing grenade bounce/fuse test remains green.

## Final verification

- `go test -race -count=1 ./...` — passed.
- `go vet ./...` — passed.
- `node tests/netcode.test.cjs` — all 30 tests passed.
- JavaScript syntax checks for `game.js`, `netcode.js` and `theme.js` — passed.
- `go build -trimpath` — passed.
- Focused Chromium grenade test — 6 assertions passed with no page errors.

An older broad Playwright script was not counted because its default bundled Chromium
binary is not installed in this environment; the focused v4.8 browser test explicitly
uses the available system Chromium executable. This does not affect the game package.
