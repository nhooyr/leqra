# v5.7.3 — barrel-aligned firing near walls

The browser, iOS, and Android renderers retract the barrel against nearby cover,
including corner grazes where the shot's width hits a wall that its centreline misses.
Recoil and wall clearance use the larger retraction rather than adding their
offsets. The barrel follows the displayed tank's angle, including during turns.

Projectile playback begins at the muzzle or the first intervening contact,
omitting the hidden path from the tank centre. Close grazing hits still resolve
along that path. Infinity and native launches stop their initial travel at the
first wall reflection, matching fixed-map launches; subsequent flight resumes
normally. Cannon retains interior-wall penetration and its existing lifetime.

Ghost is covered with its centre on the near side and its turret overlapping
the wall, including one-unit centre clearance. A reflected launch now starts at
the incoming wall face without immediately spending its remaining barrel travel
backwards. A fully retracted barrel stays hidden behind the turret rather than
protruding from the back of the tank.

Touch controls retain faster turning for large, full-tilt direction changes and
eased assistance for smaller corrections. Shared server/client movement fixtures
and native regressions cover those rates.

## Validation

- `go test -race -count=1 ./...` and `go vet ./...` passed.
- `node --test src/tests/*.test.cjs`: 1,177 passed.
- Swift core tests: 491 executed, 15 skipped, no failures. The native Swift build
  system was used because the default Swift build engine failed to resolve the
  package's own module in its existing build directory.
- Android: 219 core tests and 124 app tests, one app test skipped, no failures.
- iOS Simulator app build and Android debug app build passed.
- Embedded-server build, asset preflight, JavaScript syntax checks, shell syntax
  check, and six mocked deployment tests passed.
- `src/tests/muzzle_browser.cjs` checks real Canvas output, all seven weapons,
  head-on and grazing wall contacts, firing while turning, touch turn assistance,
  and online presentation in Chromium, Firefox, and WebKit. Its 666 cases cover
  desktop, mobile portrait, and mobile
  landscape, with iOS/Android user agents. Online checks use deterministic
  synthetic snapshots; they do not contact the public service.

Android emulator device validation also passed 40 actual online firing cases and
four touch-turn checks. These run the native GameSession, Canvas renderer and
touch handler against a disposable Go server over real WebSockets. Both fixed
maps and Infinity, portrait/landscape, all seven weapons, and Ghost turret/wall
overlap are covered. Screenshots are in
`/tmp/leqra-muzzle-device-evidence/android`.

The physical iPhone and iPhone simulator each passed the full 40 online firing
cases and four touch-turn checks with the native renderer and real WebSockets.
Both fixed maps and Infinity, portrait/landscape, all seven weapons, and Ghost
turret/wall overlap are covered. The fixture keeps existing bots away from the
test encounter and verifies firing and turning against authoritative server
state.

The optional `src/tests/muzzle_iphone.py` harness coordinates fixture setup and
authoritative checks from the Mac, so only the game app needs Local Network
permission. The game still uses native touch input and its real WebSocket
transport. iOS results are under `/tmp/leqra-muzzle-device-evidence`.

Browser reports and screenshots are written under `/tmp/leqra-ghost-muzzle-browser`.
Native logs and build output also remain outside version control. The Android
result is from an emulator, not a physical Android phone. No deployment was
performed.

The server, HTML, browser assets, and PWA version paths are synchronized at
v5.7.3. Existing image assets are unchanged.
