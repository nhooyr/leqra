# leqra for Android

Native Kotlin, hardware-accelerated Canvas graphics, low-latency PCM sound and
Android Keystore account storage. There is no WebView or JavaScript game runtime.

## Build and run

1. Install Android Studio, including Android SDK Platform 36 and Build Tools 36.
2. Open this `android` directory as the Android Studio project. Let Gradle sync.
   Select JDK 17 for Gradle (Settings → Build, Execution, Deployment → Build Tools
   → Gradle). Android Studio can download it if necessary.
3. Select the `app` run configuration and an emulator or connected Android phone,
   then click **Run ▶**. For a phone, enable Developer options and USB debugging,
   connect it, and accept its debugging prompt.

The app supports Android 8.0 (API 26) and newer. It uses the entire display in
portrait and landscape, with safe touch controls around camera cutouts and system
gestures. High refresh rate is enabled by default and requests the fastest
compatible display mode. The actual refresh rate depends on the device and its
system settings.

From the repository root, with `JAVA_HOME` pointing to JDK 17 and `ANDROID_HOME`
pointing to the Android SDK:

```sh
./android/gradlew -p android :app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.leqra/com.leqra.android.MainActivity
```

The debug APK is signed with the local Android debug key. Release builds use
`./android/gradlew -p android :app:assembleRelease`; supply your own release
signing configuration before distribution. No personal signing configuration,
device identifiers or SDK paths belong in version control. `local.properties`
and build output are ignored.

The package version and online protocol handshake read `../scripts/version.sh`,
which derives the version from `../src/main.go`. Build the Android app and server
from the same release.

## Play

Infinity, Elimination, Capture the flag, King of the hill and Survival run locally
with native physics, bots and all ten power-ups. Public Infinity, private rooms,
room rules, bots, teams, paint, matchmaking, chat and leaderboards use the same
authoritative server as the web and iOS apps. Account-key buttons beside the
callsigns manage independent P1 and P2 accounts. Import a key to move an account
between platforms; the newest Public Infinity device takes over its tank.

Touch controls steer on the left and fire on the right. Keyboard and gamepad
controls are listed in the app's Controls panel. P2 uses a keyboard or another
gamepad. Local bot names, paint, difficulty and teams are editable and retained
when publishing the same roster online. Sound effects mix with music from other
apps, including when launching muted. The default sound volume is 50%.

For local server development, run `./dev.sh` at the repository root. In a debug
build, open Settings and use `http://10.0.2.2:8080` from the Android emulator, or
your development server's address from a physical phone. Release builds require
HTTPS. Account keys are scoped to each server origin.

## Validation

```sh
./android/gradlew -p android :core:test :app:testDebugUnitTest :app:lintDebug
./android/gradlew -p android :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.server=http://10.0.2.2:8080
```

The connected tests need a fresh local server of the same version. Use an
isolated temporary `LEQRA_DATA` database, not a live leaderboard. Core regressions
consume the shared Go/browser maze, steering and wall-launch fixtures. Tests
cover all game modes, power combinations, high-speed motion, Starman load,
account cryptography, token rotation/recovery, server protocol and lifecycle.
Audio regressions compare synthesized voices and the processed mix against web
audio references.

The debug-only `RenderPerformanceTest` renders fixed and Infinity scenes in both
orientations with all power-up visuals and hundreds of projectiles. It records
Android Window FrameMetrics and saves PNGs and timings under the app's
`cache/render-benchmark` directory. These are generated test results, not source
assets. Emulator timings are useful regressions, not physical-phone performance
claims. `MainAppPerformanceTest` measures the actual Activity, including its HUD,
status and open leaderboard, with the same stress scene. It saves timings and
screenshots in `cache/main-app-benchmark`; reported deadline misses use Android's
per-frame deadline, rather than assuming every display has a 16.7 ms budget.
`NativeAudioIntegrationTest` exercises muted launch, bounded cue scheduling,
preview lifecycle, pause/resume and native audio output. Run UI and performance
checks in a disposable emulator with an isolated local server.

## Implementation

`core` is an Android-independent Kotlin simulation. Authoritative movement runs
at 60 Hz; continuous motion presentation and a bounded input/reconciliation
timeline run at the display cadence. P1 and P2 have independent prediction and
acknowledgement histories while sharing remote interpolation. Collision and bot
pathfinding use reusable primitive storage. The renderer batches rapid-fire
projectiles, rebases large world coordinates before GPU float conversion, caches
tank artwork and builds bounded maze textures on a worker. The native HUD caches
text layout while animating progress at display cadence. The audio mixer uses the
web recipes with a bounded voice pool, common compressor/limiter and lazy
AudioTrack output without requesting audio focus. Its bounded command queue never waits for waveform
synthesis or joins an output worker on the UI thread; stale cues are discarded
after an interrupted or cold audio start.

Account secrets use origin-scoped AES-GCM storage with a device-only Android
Keystore key and atomic, synced writes outside backups. New P2 credentials and
replacement-key candidates are persisted before registration or rotation. Secret
HTTP requests reject redirects. Public scores, hits and ownership are always
decided by the server; clients send controls, never scores.
