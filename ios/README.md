# leqra for iOS

A native Swift port for iPhone and iPad. SpriteKit draws the arena, UIKit handles touch and hardware-keyboard input, SwiftUI builds the mobile interface, and URLSession WebSockets connect to the existing Go server. No browser engine or JavaScript is embedded.

The interface follows the current mobile web game: the unified Ready Room, compact brand and arena bars, room settings and roster disclosures, green Play button, bottom ammunition and readiness panels, in-arena standings, portrait/landscape controls, and contextual pause menus. The tank, maze, pickup, guide, shield, Starman, and objective artwork is drawn with native vector paths and cached textures using the web renderer's geometry and palette.

## Run

1. Open `leqra.xcodeproj` in Xcode.
2. Select the **leqra** scheme and an iPhone or iPad simulator, then Run.
3. For an iPhone, select your signing team under **Signing & Capabilities**, enable Developer Mode on the phone, and Run. A free Personal Team works for development. Trust the developer profile on the phone if iOS requests it.

Requires an iOS SDK, iOS 16 or newer, and no third-party dependencies. The visible app name is lowercase **leqra**.

The app starts directly in the Ready Room. Public Infinity uses `https://leqra.com`; turn off **Public Infinity** to play locally. Expand **Room settings** to choose Infinity, Elimination, Capture the Flag, King of the Hill, or Survival. All five modes run locally in Swift. Expand **Players and bots** to edit bot names, paint, difficulty, and teams. **Share room online** publishes the current local configuration through the existing Go server.

For local online development, run `PORT=18081 go run ./src` from the repository root. Select `http://localhost:18081` as the server in the simulator, or use the Mac's LAN address on an iPhone. The app permits local networking while keeping ordinary remote connections under App Transport Security.

## Rendering and controls

The standard SpriteKit view requests up to 120 FPS, bounded by the attached display. `CADisableMinimumFrameDurationOnPhone` enables higher refresh rates on supported iPhones. Settings provides a 60 FPS option and FPS/ping display. The pause menu's measured callback rate and requested/display-rate diagnostic help verify the actual device behavior. iOS can lower the rate for power, temperature, and accessibility settings; simulator timing cannot establish physical ProMotion performance.

Simulation stays at 60 Hz. Fractional native presentation smooths local play at the display rate. Online movement uses acknowledged-input replay and a bounded remote interpolation buffer; the server owns damage, pickups, respawns, and scores. Pausing clears controls. Online arenas continue, and Infinity holds a paused pilot's respawn. Backgrounding pauses the native client and releases held controls.

Drag the left stick to drive and aim; hold Fire to shoot. Grenades use a new press to throw or detonate. Hardware keyboards support WASD/arrow keys and Q/C/Space for Fire.

Native sound uses the browser's sine/triangle voices, exponential pitch and volume envelopes, layered pickup notes, and filtered explosion noise. Cached PCM feeds a bounded voice pool and shared browser-matched compressor/limiter; volume defaults to 50% and can be adjusted in Settings. Native sound honors the silent switch, mixes with other audio, and adds local haptic cues.

## Online rooms

The client supports public Infinity, private fixed/Infinity rooms, names and paint, bot/role/team editing, rules and local presets, readiness, invitations, room and opponent chat, matchmaking consent/search/cancellation, reports, and session recovery. Public Infinity automatically rejoins after backgrounding, connection loss, or reopening an active run. Its server-issued bearer stays in a non-synchronizing, device-only Keychain entry scoped to the server origin; scores always come from the server. Explicit Exit stops automatic rejoining while retaining that identity for a later Play. Private room tokens remain in memory for their bounded retry window and are never persisted to disk. The durable bearer also proves online callsign ownership across public and private modes. Inline availability feedback reserves its space while editing; offline callsigns remain unrestricted.

The displayed version, `NetworkClient.supportedVersion`, and the app bundle's release version are generated from `src/main.go` through `scripts/version.sh` on each relevant build. Xcode and `swift test` regenerate the core constant when that source changes; Xcode also generates the bundle's `Info.plist` in its build directory. No manual native version update is needed. The client validates `/api/build` and the room handshake, so release changes still require compatible protocol and gameplay behavior. `CURRENT_PROJECT_VERSION` remains the separate iOS build counter.

Open **Account key** in the ready room or Settings to copy an existing account to another trusted device. The key stays masked; explicit Copy supports Universal Clipboard and expires from the clipboard after ten minutes. Import checks the key and previews its reserved callsigns and public score before replacing the current device's key. Import and Reset require the offline ready room. Reset retains names and scores while signing out all other devices. Its replacement is saved as a pending Keychain record before the server request, so a lost response or app termination can be recovered by reopening Account key. Keys are bound to the selected server and never stored in preferences. If a key is lost, copy it from another signed-in device or ask for manual help on the repository's GitHub issues; recovery is not automatic.

P1 and P2 have separate keys. Their Account buttons sit beside their callsign fields; Settings also exposes P2's key when its room row is unavailable. Importing or resetting P2 does not replace P1's key or callsign. A P2 key can become P1 on another device. Fresh P2 proofs are saved before the first online join, with independent Keychain backups retained when an interrupted registration could still commit. A saved activation is offered for explicit review instead of silently replacing a subsequently imported account. The native client requires a matching P2 proof in the server's welcome; an older server cannot silently fall back to a shared P1/P2 account.

## Validate

From the repository root, with Xcode selected (or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`):

```sh
swift test --package-path ios

# Optional live checks against a disposable local server:
LEQRA_TEST_SERVER=http://127.0.0.1:18081 swift test --package-path ios

xcodebuild -project ios/leqra.xcodeproj -scheme leqra \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/leqra-ios-build CODE_SIGNING_ALLOWED=NO build

# Choose a simulator from `xcrun simctl list devices available`:
xcodebuild -project ios/leqra.xcodeproj -scheme leqra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/leqra-ios-build CODE_SIGNING_ALLOWED=NO test
```

UI tests expect a local Go server on port 18081. They cover Ready Room configuration, all local modes, native touch controls, portrait/landscape layout, pause/settings, in-arena standings, and private Infinity → lobby → fixed-match transitions. Prefix the test command with `TEST_RUNNER_LEQRA_RENDER_STRESS_UI=1` to include all ten power-ups with stacked buffs and a ricochet renderer fixture. Screenshots stay in the XCTest result bundle. Live transport tests create disposable pilots and rooms on the selected server.

Core regressions compare maze hashes and steering with the existing Go/browser fixtures, and cover weapons, geometry, objectives, survival, rendering history, HUD presentation, room editing, and reconnects. Generated build/test artifacts belong in `/tmp` or ignored build directories.

Set `LEQRA_TEST_SERVER` to a disposable server when running the core live recovery regression. The UI recovery test additionally requires `TEST_RUNNER_LEQRA_PUBLIC_RECOVERY_UI=1` with a normally signed `xcodebuild` simulator build; disabling code signing prevents Keychain storage. It validates actual Keychain recovery after termination, explicit Exit, online name ownership, stable inline feedback, and unrestricted offline play. UI fixtures use a separate Keychain namespace and unique callsigns so they never clear a normal app identity.

Give the recovery UI test a fresh database for each run, separate from other live tests. It verifies the recovered ID through the public top ten, so archived pilots from previous tests must not occupy those rows:

```sh
LEQRA_DATA="$(mktemp -d)/data.sqlite" LEQRA_ADMIN_ADDR=off PORT=18081 go run ./src
```

For renderer profiling, add `--native-performance-probe --probe-weapon cannon --probe-bullets 115 --probe-pan` under **Product → Scheme → Edit Scheme → Run → Arguments**. The opt-in synthetic scene prints frame-time percentiles, CPU stages, map raster/install timings, and allocation counters after a three-second warmup. Use `--probe-weapon laser`, `--probe-buffs shield,speed,ghost`, or `--probe-bounces` to exercise other rendering paths. Add `--probe-motion keyboard` or `--probe-motion touch` for Speed ×5 turns through the shared 60 Hz movement and presentation code, with velocity, acceleration, and jerk measurements. This motion fixture uses Ghost to isolate free movement from wall collisions. These scenes do not join online games or change ordinary gameplay. Remove the arguments to return to normal play; keep captured output outside the repository.

The native bot tiers use compact pathfinding and difficulty tuning rather than the complete browser/Go Godlike forecasting strategy. Keyboard-only local co-pilot/split-screen controls are not exposed by this mobile client. The native UI uses iOS text entry, menus, sharing, and accessibility rather than browser-specific dialogs or mouse/fullscreen APIs.
